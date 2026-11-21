-- Correct lease expiry checks after ledger-row lock waits.
-- Migration 020 remains immutable; this additive migration replaces its four
-- transport-sensitive transitions using wall-clock time after row locking.
begin;
do $$
begin
  if to_regprocedure('public.authorize_delivery_job(uuid,uuid)') is null
    or to_regprocedure('public.retry_delivery_job(uuid,uuid,timestamptz,text)') is null
    or to_regprocedure('public.mark_delivery_sent(uuid,uuid,text)') is null
    or to_regprocedure('public.mark_delivery_failed(uuid,uuid,text)') is null then
    raise exception 'Migration 028 requires the reviewed delivery reliability RPCs.';
  end if;
end;
$$;

create or replace function public.authorize_delivery_job(p_job_id uuid, p_claim_token uuid)
returns boolean language plpgsql security definer
set search_path = public, auth, pg_temp
as $authorize$
declare
  v_job public.delivery_ledger%rowtype;
  v_authorized boolean := false;
  v_now timestamptz;
begin
  if p_job_id is null or p_claim_token is null then
    raise exception 'A job ID and claim token are required.' using errcode = '22023';
  end if;
  select * into v_job from public.delivery_ledger dl where dl.id = p_job_id for update;
  -- now() is fixed at transaction start and is unsafe after a row-lock wait.
  v_now := clock_timestamp();
  if not found or v_job.state <> 'claimed'
     or v_job.claim_token is distinct from p_claim_token
     or v_job.claim_expires_at is null or v_job.claim_expires_at <= v_now then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  if v_job.kind = 'daily_reminder' then
    select exists (
      select 1 from public.daily_reminder_preferences drp
      join public.profiles p on p.user_id = drp.user_id and p.is_suspended = false
      join pg_catalog.pg_timezone_names tz on tz.name = drp.timezone
      where drp.user_id = v_job.user_id and drp.daily_enabled = true
        and v_job.delivery_key = 'daily:' || timezone(drp.timezone, v_job.scheduled_for)::date::text
        and v_job.scheduled_for = (
          (timezone(drp.timezone, v_job.scheduled_for)::date + drp.reminder_time)
          at time zone drp.timezone
        )
    ) into v_authorized;
  elsif v_job.kind = 'weekly_newsletter' then
    select exists (
      select 1 from public.newsletter_preferences np
      join public.profiles p on p.user_id = np.user_id and p.is_suspended = false
      join auth.users u on u.id = np.user_id
        and u.email_confirmed_at is not null and nullif(btrim(u.email), '') is not null
      join public.weekly_goodness_features f
        on v_job.delivery_key = 'weekly:' || f.week_start::text
      where np.user_id = v_job.user_id and np.weekly_enabled = true and np.consented_at is not null
    ) into v_authorized;
  else
    raise exception 'Unsupported delivery kind.' using errcode = '22023';
  end if;

  -- Authorization reads may themselves take time; recheck before any result.
  v_now := clock_timestamp();
  if v_job.claim_expires_at <= v_now then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;
  if not v_authorized then
    update public.delivery_ledger set
      state = 'cancelled', cancelled_at = clock_timestamp(),
      claim_token = null, claim_expires_at = null, next_attempt_at = null,
      error_code = 'authorization_revoked', updated_at = clock_timestamp()
    where id = v_job.id and state = 'claimed' and claim_token = p_claim_token
      and claim_expires_at > clock_timestamp();
    if not found then
      raise exception 'Delivery claim is not authorized.' using errcode = '42501';
    end if;
    return false;
  end if;
  return true;
end;
$authorize$;
revoke all privileges on function public.authorize_delivery_job(uuid, uuid) from public, anon, authenticated;
grant execute on function public.authorize_delivery_job(uuid, uuid) to service_role;

create or replace function public.retry_delivery_job(
  p_job_id uuid, p_claim_token uuid, p_retry_at timestamptz, p_error_code text
)
returns boolean language plpgsql security definer
set search_path = public, auth, pg_temp
as $retry$
declare
  v_job public.delivery_ledger%rowtype;
  v_error_code text := btrim(coalesce(p_error_code, ''));
  v_now timestamptz;
begin
  if p_job_id is null or p_claim_token is null or p_retry_at is null then
    raise exception 'A job ID, claim token, and retry time are required.' using errcode = '22023';
  end if;
  if char_length(v_error_code) < 1 or char_length(v_error_code) > 100 then
    raise exception 'A bounded error code is required.' using errcode = '22023';
  end if;
  select * into v_job from public.delivery_ledger dl where dl.id = p_job_id for update;
  v_now := clock_timestamp();
  if not found or v_job.state <> 'claimed'
     or v_job.claim_token is distinct from p_claim_token
     or v_job.claim_expires_at is null or v_job.claim_expires_at <= v_now then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;
  if p_retry_at <= v_now or p_retry_at > v_now + interval '24 hours' then
    raise exception 'Retry time must be within the next 24 hours.' using errcode = '22023';
  end if;
  if v_job.attempt_count >= 5 then
    update public.delivery_ledger set
      state = 'failed', failed_at = clock_timestamp(),
      claim_token = null, claim_expires_at = null, next_attempt_at = null,
      error_code = 'retry_exhausted', updated_at = clock_timestamp()
    where id = v_job.id and state = 'claimed' and claim_token = p_claim_token
      and claim_expires_at > clock_timestamp();
    if not found then
      raise exception 'Delivery claim is not authorized.' using errcode = '42501';
    end if;
    return false;
  end if;
  update public.delivery_ledger set
    state = 'queued', claim_token = null, claim_expires_at = null,
    next_attempt_at = p_retry_at, error_code = v_error_code, updated_at = clock_timestamp()
  where id = v_job.id and state = 'claimed' and claim_token = p_claim_token
    and claim_expires_at > clock_timestamp();
  if not found then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;
  return true;
end;
$retry$;
revoke all privileges on function public.retry_delivery_job(uuid, uuid, timestamptz, text)
from public, anon, authenticated;
grant execute on function public.retry_delivery_job(uuid, uuid, timestamptz, text) to service_role;

create or replace function public.mark_delivery_sent(
  p_job_id uuid, p_claim_token uuid, p_provider_result_id text default null
)
returns boolean language plpgsql security definer
set search_path = public, auth, pg_temp
as $sent$
declare
  v_job public.delivery_ledger%rowtype;
  v_now timestamptz;
begin
  if p_provider_result_id is not null and char_length(p_provider_result_id) > 255 then
    raise exception 'Provider result identifier is too long.' using errcode = '22023';
  end if;
  select * into v_job from public.delivery_ledger dl where dl.id = p_job_id for update;
  v_now := clock_timestamp();
  if not found or v_job.state <> 'claimed'
     or v_job.claim_token is distinct from p_claim_token
     or v_job.claim_expires_at is null or v_job.claim_expires_at <= v_now then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;
  update public.delivery_ledger set
    state = 'sent', sent_at = clock_timestamp(),
    claim_token = null, claim_expires_at = null, next_attempt_at = null,
    provider_result_id = nullif(btrim(p_provider_result_id), ''),
    error_code = null, updated_at = clock_timestamp()
  where id = v_job.id and state = 'claimed' and claim_token = p_claim_token
    and claim_expires_at > clock_timestamp();
  if not found then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;
  return true;
end;
$sent$;
revoke all privileges on function public.mark_delivery_sent(uuid, uuid, text)
from public, anon, authenticated;
grant execute on function public.mark_delivery_sent(uuid, uuid, text) to service_role;

create or replace function public.mark_delivery_failed(
  p_job_id uuid, p_claim_token uuid, p_error_code text
)
returns boolean language plpgsql security definer
set search_path = public, auth, pg_temp
as $failed$
declare
  v_job public.delivery_ledger%rowtype;
  v_error_code text := btrim(coalesce(p_error_code, ''));
  v_now timestamptz;
begin
  if char_length(v_error_code) < 1 or char_length(v_error_code) > 100 then
    raise exception 'A bounded error code is required.' using errcode = '22023';
  end if;
  select * into v_job from public.delivery_ledger dl where dl.id = p_job_id for update;
  v_now := clock_timestamp();
  if not found or v_job.state <> 'claimed'
     or v_job.claim_token is distinct from p_claim_token
     or v_job.claim_expires_at is null or v_job.claim_expires_at <= v_now then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;
  update public.delivery_ledger set
    state = 'failed', failed_at = clock_timestamp(),
    claim_token = null, claim_expires_at = null, next_attempt_at = null,
    error_code = v_error_code, updated_at = clock_timestamp()
  where id = v_job.id and state = 'claimed' and claim_token = p_claim_token
    and claim_expires_at > clock_timestamp();
  if not found then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;
  return true;
end;
$failed$;
revoke all privileges on function public.mark_delivery_failed(uuid, uuid, text)
from public, anon, authenticated;
grant execute on function public.mark_delivery_failed(uuid, uuid, text) to service_role;

notify pgrst, 'reload schema';
commit;
