-- Make provider idempotency timing database-authoritative and validate Resend receipts.
begin;
do $migration_030_preflight$
declare
  v_crypto_schema text;
  v_authorize_oid oid := to_regprocedure('public.authorize_delivery_job(uuid,uuid)');
  v_failed_oid oid := to_regprocedure('public.mark_delivery_failed(uuid,uuid,text)');
  v_authorize_source text;
  v_failed_source text;
  v_authorize_hash text;
  v_failed_hash text;
  v_authorize_definer boolean;
  v_failed_definer boolean;
  v_authorize_config text[];
  v_failed_config text[];
  v_authorize_language text;
  v_failed_language text;
begin
  if v_authorize_oid is null
    or v_failed_oid is null
    or to_regprocedure('public.retry_delivery_job(uuid,uuid,timestamptz,text)') is null
    or to_regprocedure('public.mark_delivery_sent(uuid,uuid,text)') is null
    or not exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'delivery_ledger'
        and column_name = 'transport_started_at'
    ) then
    raise exception 'Migration 030 requires the exact hardened migration-028 authorize_delivery_job and mark_delivery_failed implementations.';
  end if;

  select n.nspname into v_crypto_schema
  from pg_catalog.pg_extension e
  join pg_catalog.pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';

  if v_crypto_schema is null then
    raise exception 'Migration 030 requires pgcrypto to attest migration-028 function source.';
  end if;

  select p.prosrc, p.prosecdef, p.proconfig, l.lanname
  into v_authorize_source, v_authorize_definer, v_authorize_config, v_authorize_language
  from pg_catalog.pg_proc p
  join pg_catalog.pg_language l on l.oid = p.prolang
  where p.oid = v_authorize_oid;

  select p.prosrc, p.prosecdef, p.proconfig, l.lanname
  into v_failed_source, v_failed_definer, v_failed_config, v_failed_language
  from pg_catalog.pg_proc p
  join pg_catalog.pg_language l on l.oid = p.prolang
  where p.oid = v_failed_oid;

  execute format(
    'select encode(%I.digest(convert_to($1, ''UTF8''), ''sha256''), ''hex'')',
    v_crypto_schema
  ) into v_authorize_hash using v_authorize_source;

  execute format(
    'select encode(%I.digest(convert_to($1, ''UTF8''), ''sha256''), ''hex'')',
    v_crypto_schema
  ) into v_failed_hash using v_failed_source;

  if v_authorize_hash is distinct from 'dea4d0ecb1518edec6c60f1ec998669af65b2164a547cffe67f5cbdaa8644215'
    or v_failed_hash is distinct from 'c7830ca2281fa85e4466fa45c32c1067dba4c9766eeeb26d26dcdb3b46b72b78'
    or v_authorize_language is distinct from 'plpgsql'
    or v_failed_language is distinct from 'plpgsql'
    or v_authorize_definer is distinct from true
    or v_failed_definer is distinct from true
    or v_authorize_config is distinct from array['search_path=public, auth, pg_temp']::text[]
    or v_failed_config is distinct from array['search_path=public, auth, pg_temp']::text[] then
    raise exception 'Migration 030 requires the exact hardened migration-028 authorize_delivery_job and mark_delivery_failed implementations.';
  end if;

  if has_function_privilege('anon', v_authorize_oid, 'EXECUTE')
    or has_function_privilege('authenticated', v_authorize_oid, 'EXECUTE')
    or not has_function_privilege('service_role', v_authorize_oid, 'EXECUTE')
    or has_function_privilege('anon', v_failed_oid, 'EXECUTE')
    or has_function_privilege('authenticated', v_failed_oid, 'EXECUTE')
    or not has_function_privilege('service_role', v_failed_oid, 'EXECUTE')
    or exists (
      select 1
      from pg_catalog.pg_proc p
      cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      where p.oid in (v_authorize_oid, v_failed_oid)
        and a.grantee = 0
        and a.privilege_type = 'EXECUTE'
    ) then
    raise exception 'Migration 030 requires migration-028 service-role-only RPC privileges.';
  end if;
end;
$migration_030_preflight$;

drop function if exists public.authorize_delivery_idempotency_window(uuid,uuid);
create function public.authorize_delivery_idempotency_window(p_job_id uuid,p_claim_token uuid)
returns text language plpgsql security definer
set search_path = public, auth, pg_temp
as $idempotency$
declare v_job public.delivery_ledger%rowtype; v_now timestamptz;
begin
  if p_job_id is null or p_claim_token is null then raise exception 'A job ID and claim token are required.' using errcode='22023'; end if;
  -- Re-run the full consent/profile/claim authorization after transport start and immediately before send.
  if public.authorize_delivery_job(p_job_id,p_claim_token) is not true then return 'cancelled'; end if;
  select * into v_job from public.delivery_ledger dl where dl.id=p_job_id for update;
  v_now := clock_timestamp();
  if not found or v_job.state <> 'claimed' or v_job.claim_token is distinct from p_claim_token
    or v_job.claim_expires_at is null or v_job.claim_expires_at <= v_now or v_job.transport_started_at is null then
    raise exception 'Delivery claim is not authorized for provider transport.' using errcode='42501';
  end if;
  if v_job.transport_started_at + interval '23 hours' <= v_now + interval '30 seconds' then
    update public.delivery_ledger set state='failed',failed_at=clock_timestamp(),claim_token=null,
      claim_expires_at=null,next_attempt_at=null,error_code='provider_idempotency_window_expired',updated_at=clock_timestamp()
    where id=v_job.id and state='claimed' and claim_token=p_claim_token and claim_expires_at > clock_timestamp();
    if not found then raise exception 'Delivery claim is not authorized for provider transport.' using errcode='42501'; end if;
    return 'expired';
  end if;
  return 'authorized';
end;
$idempotency$;
revoke all privileges on function public.authorize_delivery_idempotency_window(uuid,uuid) from public,anon,authenticated;
grant execute on function public.authorize_delivery_idempotency_window(uuid,uuid) to service_role;
comment on function public.authorize_delivery_idempotency_window(uuid,uuid)
is 'deedlight:030:database-authoritative-provider-idempotency-horizon:v1';

create or replace function public.retry_delivery_job(p_job_id uuid,p_claim_token uuid,p_error_code text)
returns boolean language plpgsql security definer
set search_path = public, auth, pg_temp
as $retry$
declare v_job public.delivery_ledger%rowtype; v_error text:=btrim(coalesce(p_error_code,'')); v_now timestamptz; v_retry_at timestamptz;
begin
  if p_job_id is null or p_claim_token is null then raise exception 'A job ID and claim token are required.' using errcode='22023'; end if;
  if char_length(v_error)<1 or char_length(v_error)>100 then raise exception 'A bounded error code is required.' using errcode='22023'; end if;
  select * into v_job from public.delivery_ledger dl where dl.id=p_job_id for update;
  v_now:=clock_timestamp();
  if not found or v_job.state<>'claimed' or v_job.claim_token is distinct from p_claim_token
    or v_job.claim_expires_at is null or v_job.claim_expires_at<=v_now or v_job.transport_started_at is null then
    raise exception 'Delivery claim is not authorized for retry.' using errcode='42501';
  end if;
  if v_job.attempt_count>=5 then
    update public.delivery_ledger set state='failed',failed_at=clock_timestamp(),claim_token=null,claim_expires_at=null,
      next_attempt_at=null,error_code='retry_exhausted',updated_at=clock_timestamp()
    where id=v_job.id and state='claimed' and claim_token=p_claim_token and claim_expires_at>clock_timestamp();
    if not found then raise exception 'Delivery claim is not authorized for retry.' using errcode='42501'; end if;
    return false;
  end if;
  v_retry_at:=v_now+interval '5 minutes';
  if v_job.transport_started_at+interval '23 hours'<=v_retry_at+interval '30 seconds' then
    update public.delivery_ledger set state='failed',failed_at=clock_timestamp(),claim_token=null,claim_expires_at=null,
      next_attempt_at=null,error_code='provider_idempotency_window_expired',updated_at=clock_timestamp()
    where id=v_job.id and state='claimed' and claim_token=p_claim_token and claim_expires_at>clock_timestamp();
    if not found then raise exception 'Delivery claim is not authorized for retry.' using errcode='42501'; end if;
    return false;
  end if;
  update public.delivery_ledger set state='queued',claim_token=null,claim_expires_at=null,next_attempt_at=v_retry_at,
    error_code=v_error,updated_at=clock_timestamp()
  where id=v_job.id and state='claimed' and claim_token=p_claim_token and claim_expires_at>clock_timestamp()
    and transport_started_at+interval '23 hours'>clock_timestamp()+interval '5 minutes 30 seconds';
  if not found then
    update public.delivery_ledger set state='failed',failed_at=clock_timestamp(),claim_token=null,claim_expires_at=null,
      next_attempt_at=null,error_code='provider_idempotency_window_expired',updated_at=clock_timestamp()
    where id=v_job.id and state='claimed' and claim_token=p_claim_token and claim_expires_at>clock_timestamp()
      and transport_started_at+interval '23 hours'<=clock_timestamp()+interval '5 minutes 30 seconds';
    if found then return false; end if;
    raise exception 'Delivery claim is not authorized for retry.' using errcode='42501';
  end if;
  return true;
end;
$retry$;
revoke all privileges on function public.retry_delivery_job(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.retry_delivery_job(uuid,uuid,text) to service_role;
comment on function public.retry_delivery_job(uuid,uuid,text)
is 'deedlight:030:database-authoritative-retry-time-and-provider-horizon:v1';

create or replace function public.retry_delivery_job(p_job_id uuid,p_claim_token uuid,p_retry_at timestamptz,p_error_code text)
returns boolean language plpgsql security definer
set search_path = public, auth, pg_temp
as $legacy_retry$
begin return public.retry_delivery_job(p_job_id,p_claim_token,p_error_code); end;
$legacy_retry$;
revoke all privileges on function public.retry_delivery_job(uuid,uuid,timestamptz,text) from public,anon,authenticated;
grant execute on function public.retry_delivery_job(uuid,uuid,timestamptz,text) to service_role;
comment on function public.retry_delivery_job(uuid,uuid,timestamptz,text)
is 'deedlight:030:legacy-retry-timestamp-ignored:v1';

create or replace function public.mark_delivery_sent(p_job_id uuid,p_claim_token uuid,p_provider_result_id text default null)
returns boolean language plpgsql security definer
set search_path = public, auth, pg_temp
as $sent$
declare v_job public.delivery_ledger%rowtype; v_now timestamptz;
begin
  select * into v_job from public.delivery_ledger dl where dl.id=p_job_id for update;
  v_now:=clock_timestamp();
  if not found or v_job.state<>'claimed' or v_job.claim_token is distinct from p_claim_token
    or v_job.claim_expires_at is null or v_job.claim_expires_at<=v_now or v_job.transport_started_at is null then
    raise exception 'Delivery claim is not authorized for sent transition.' using errcode='42501';
  end if;
  if p_provider_result_id is null or char_length(p_provider_result_id)<>36
    or p_provider_result_id<>btrim(p_provider_result_id)
    or p_provider_result_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'A valid Resend email identifier is required.' using errcode='22023';
  end if;
  update public.delivery_ledger set state='sent',sent_at=clock_timestamp(),claim_token=null,claim_expires_at=null,
    next_attempt_at=null,provider_result_id=p_provider_result_id,error_code=null,updated_at=clock_timestamp()
  where id=v_job.id and state='claimed' and claim_token=p_claim_token and claim_expires_at>clock_timestamp()
    and transport_started_at is not null;
  if not found then raise exception 'Delivery claim is not authorized for sent transition.' using errcode='42501'; end if;
  return true;
end;
$sent$;
revoke all privileges on function public.mark_delivery_sent(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.mark_delivery_sent(uuid,uuid,text) to service_role;
comment on function public.mark_delivery_sent(uuid,uuid,text)
is 'deedlight:030:validated-resend-receipt-and-transport-evidence:v1';
notify pgrst,'reload schema';
commit;
