\set ON_ERROR_STOP on

-- Re-prove the complete Sprint 12.2 behavior first, then harden that state.
\ir test-sprint12-2-delivery.sql
\ir ../supabase/migrations/202609230020_delivery_reliability_hardening.sql

-- New reliability metadata and RPCs remain service-role only.
do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'delivery_ledger'
      and column_name = 'claim_expires_at'
  )
  or not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'delivery_ledger'
      and column_name = 'attempt_count'
  )
  or not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'delivery_ledger'
      and column_name = 'last_attempt_at'
  )
  or not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'delivery_ledger'
      and column_name = 'next_attempt_at'
  ) then
    raise exception 'Delivery reliability metadata is incomplete.';
  end if;

  if has_function_privilege(
      'anon',
      'public.retry_delivery_job(uuid,uuid,timestamp with time zone,text)',
      'EXECUTE'
    )
    or has_function_privilege(
      'authenticated',
      'public.retry_delivery_job(uuid,uuid,timestamp with time zone,text)',
      'EXECUTE'
    ) then
    raise exception 'Browser roles must not execute delivery retry RPCs.';
  end if;

  if not has_function_privilege(
      'service_role',
      'public.retry_delivery_job(uuid,uuid,timestamp with time zone,text)',
      'EXECUTE'
    ) then
    raise exception 'Service role delivery retry execution is missing.';
  end if;
end;
$$;

-- Prepare one new, currently authorized Weekly Goodness delivery.
insert into public.weekly_goodness_features (week_start)
values ('2026-09-28')
on conflict (week_start) do nothing;

insert into public.delivery_ledger (
  user_id,
  kind,
  delivery_key,
  scheduled_for
)
values (
  '00000000-0000-0000-0000-000000000002',
  'weekly_newsletter',
  'weekly:2026-09-28',
  now() - interval '1 minute'
);

set role service_role;
do $$
declare
  v_id uuid;
  v_original_scheduled timestamptz;
  v_after_scheduled timestamptz;
  v_token_1 uuid;
  v_token_2 uuid;
  v_token_3 uuid;
  v_token_4 uuid;
  v_token_5 uuid;
  v_count integer;
  v_attempt_count integer;
  v_claim_expires_at timestamptz;
  v_next_attempt_at timestamptz;
  v_retry_result boolean;
begin
  select job_id, claim_token
  into v_id, v_token_1
  from public.claim_delivery_jobs(now(), 10)
  where delivery_key = 'weekly:2026-09-28';

  if v_id is null or v_token_1 is null then
    raise exception 'Initial reliability claim was not returned.';
  end if;

  select scheduled_for, attempt_count, claim_expires_at
  into v_original_scheduled, v_attempt_count, v_claim_expires_at
  from public.delivery_ledger
  where id = v_id;

  if v_attempt_count <> 1 then
    raise exception 'Initial claim did not increment attempt_count.';
  end if;

  if v_claim_expires_at <= now()
     or v_claim_expires_at > now() + interval '6 minutes' then
    raise exception 'Initial claim lease is not finite and bounded.';
  end if;

  select count(*) into v_count
  from public.claim_delivery_jobs(now(), 10);

  if v_count <> 0 then
    raise exception 'A live claim was stolen before lease expiry.';
  end if;

  -- Force the first lease to expire. All transport-sensitive operations must fail closed.
  update public.delivery_ledger
  set claim_expires_at = now() - interval '1 second'
  where id = v_id;

  begin
    perform public.authorize_delivery_job(v_id, v_token_1);
    raise exception 'Expired claim unexpectedly authorized.';
  exception when sqlstate '42501' then
    null;
  end;

  begin
    perform public.mark_delivery_sent(v_id, v_token_1, 'expired-token');
    raise exception 'Expired claim unexpectedly marked sent.';
  exception when sqlstate '42501' then
    null;
  end;

  begin
    perform public.mark_delivery_failed(v_id, v_token_1, 'expired_token');
    raise exception 'Expired claim unexpectedly marked failed.';
  exception when sqlstate '42501' then
    null;
  end;

  -- Expired lease is reclaimed with a fresh token and a second attempt.
  select claim_token
  into v_token_2
  from public.claim_delivery_jobs(now(), 10)
  where job_id = v_id;

  if v_token_2 is null or v_token_2 = v_token_1 then
    raise exception 'Expired claim was not reclaimed with a fresh token.';
  end if;

  select attempt_count into v_attempt_count
  from public.delivery_ledger
  where id = v_id;

  if v_attempt_count <> 2 then
    raise exception 'Reclaim did not increment attempt_count.';
  end if;

  begin
    perform public.retry_delivery_job(
      v_id,
      v_token_1,
      now() + interval '10 minutes',
      'stale_token'
    );
    raise exception 'Stale claim token unexpectedly retried a reclaimed job.';
  exception when sqlstate '42501' then
    null;
  end;

  begin
    perform public.mark_delivery_sent(v_id, v_token_1, 'stale-token');
    raise exception 'Stale claim token unexpectedly marked a reclaimed job sent.';
  exception when sqlstate '42501' then
    null;
  end;

  if public.authorize_delivery_job(v_id, v_token_2) is not true then
    raise exception 'Current reclaimed job authorization unexpectedly failed.';
  end if;

  -- Temporary failure requeues without changing the semantic scheduled_for.
  v_retry_result := public.retry_delivery_job(
    v_id,
    v_token_2,
    now() + interval '10 minutes',
    'provider_temporarily_unavailable'
  );

  if v_retry_result is not true then
    raise exception 'Temporary failure did not requeue.';
  end if;

  select scheduled_for, next_attempt_at
  into v_after_scheduled, v_next_attempt_at
  from public.delivery_ledger
  where id = v_id
    and state = 'queued'
    and claim_token is null
    and claim_expires_at is null;

  if not found or v_next_attempt_at is null then
    raise exception 'Requeued job did not preserve safe queued state.';
  end if;

  if v_after_scheduled is distinct from v_original_scheduled then
    raise exception 'Retry changed the semantic scheduled_for timestamp.';
  end if;

  select count(*) into v_count
  from public.claim_delivery_jobs(now() + interval '5 minutes', 10);

  if v_count <> 0 then
    raise exception 'Job was claimable before next_attempt_at.';
  end if;

  -- Third attempt becomes available after the retry delay.
  select claim_token
  into v_token_3
  from public.claim_delivery_jobs(now() + interval '11 minutes', 10)
  where job_id = v_id;

  if v_token_3 is null or v_token_3 = v_token_2 then
    raise exception 'Delayed retry was not claimed with a fresh token.';
  end if;

  select attempt_count into v_attempt_count
  from public.delivery_ledger
  where id = v_id;

  if v_attempt_count <> 3 then
    raise exception 'Delayed retry did not become attempt three.';
  end if;

  -- Allow lease expiry to drive attempts four and five.
  select claim_token
  into v_token_4
  from public.claim_delivery_jobs(now() + interval '17 minutes', 10)
  where job_id = v_id;

  if v_token_4 is null or v_token_4 = v_token_3 then
    raise exception 'Attempt four reclaim failed.';
  end if;

  select claim_token
  into v_token_5
  from public.claim_delivery_jobs(now() + interval '23 minutes', 10)
  where job_id = v_id;

  if v_token_5 is null or v_token_5 = v_token_4 then
    raise exception 'Attempt five reclaim failed.';
  end if;

  select attempt_count into v_attempt_count
  from public.delivery_ledger
  where id = v_id;

  if v_attempt_count <> 5 then
    raise exception 'Attempt limit was not reached exactly at five.';
  end if;

  -- Once attempt five expires, the claim sweep makes it terminal and returns no replacement claim.
  select count(*) into v_count
  from public.claim_delivery_jobs(now() + interval '29 minutes', 10)
  where job_id = v_id;

  if v_count <> 0 then
    raise exception 'Retry-exhausted job was reclaimed beyond the attempt limit.';
  end if;

  if not exists (
    select 1
    from public.delivery_ledger
    where id = v_id
      and state = 'failed'
      and attempt_count = 5
      and error_code = 'retry_exhausted'
      and claim_token is null
      and claim_expires_at is null
  ) then
    raise exception 'Retry exhaustion did not become a safe terminal failure.';
  end if;
end;
$$;
reset role;

select jsonb_build_object(
  'delivery_reliability', 'pass',
  'retry_exhausted_jobs', count(*) filter (
    where state = 'failed' and error_code = 'retry_exhausted'
  ),
  'max_attempt_count', max(attempt_count)
) as delivery_reliability_behavior
from public.delivery_ledger;
