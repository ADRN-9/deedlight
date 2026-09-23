\set ON_ERROR_STOP on

-- Run the full lease/reclaim/retry suite first.
\ir test-delivery-reliability.sql

-- Exercise the post-hardening terminal transitions with live claim leases.
insert into public.weekly_goodness_features (week_start)
values
  ('2026-10-05'),
  ('2026-10-12'),
  ('2026-10-19')
on conflict (week_start) do nothing;

insert into public.delivery_ledger (
  user_id,
  kind,
  delivery_key,
  scheduled_for,
  attempt_count
)
values
  (
    '00000000-0000-0000-0000-000000000002',
    'weekly_newsletter',
    'weekly:2026-10-05',
    now() - interval '3 minutes',
    0
  ),
  (
    '00000000-0000-0000-0000-000000000002',
    'weekly_newsletter',
    'weekly:2026-10-12',
    now() - interval '2 minutes',
    0
  ),
  (
    '00000000-0000-0000-0000-000000000002',
    'weekly_newsletter',
    'weekly:2026-10-19',
    now() - interval '1 minute',
    4
  );

set role service_role;
do $$
declare
  v_sent_id uuid;
  v_failed_id uuid;
  v_exhausted_id uuid;
  v_sent_token uuid;
  v_failed_token uuid;
  v_exhausted_token uuid;
  v_retry_result boolean;
begin
  -- One claim pass should pick all three due jobs. The seeded fourth-attempt
  -- job becomes attempt five here.
  perform * from public.claim_delivery_jobs(now(), 10);

  select id, claim_token into v_sent_id, v_sent_token
  from public.delivery_ledger
  where delivery_key = 'weekly:2026-10-05';

  select id, claim_token into v_failed_id, v_failed_token
  from public.delivery_ledger
  where delivery_key = 'weekly:2026-10-12';

  select id, claim_token into v_exhausted_id, v_exhausted_token
  from public.delivery_ledger
  where delivery_key = 'weekly:2026-10-19';

  if v_sent_token is null or v_failed_token is null or v_exhausted_token is null then
    raise exception 'Terminal-transition fixtures were not all claimed.';
  end if;

  if public.authorize_delivery_job(v_sent_id, v_sent_token) is not true then
    raise exception 'Live sent fixture was not authorized.';
  end if;

  if public.mark_delivery_sent(v_sent_id, v_sent_token, 'provider-message-123') is not true then
    raise exception 'Live claim could not be marked sent.';
  end if;

  if not exists (
    select 1
    from public.delivery_ledger
    where id = v_sent_id
      and state = 'sent'
      and provider_result_id = 'provider-message-123'
      and sent_at is not null
      and claim_token is null
      and claim_expires_at is null
  ) then
    raise exception 'Sent transition did not invalidate the live claim safely.';
  end if;

  if public.authorize_delivery_job(v_failed_id, v_failed_token) is not true then
    raise exception 'Live permanent-failure fixture was not authorized.';
  end if;

  if public.mark_delivery_failed(v_failed_id, v_failed_token, 'provider_rejected') is not true then
    raise exception 'Live claim could not be marked permanently failed.';
  end if;

  if not exists (
    select 1
    from public.delivery_ledger
    where id = v_failed_id
      and state = 'failed'
      and error_code = 'provider_rejected'
      and failed_at is not null
      and claim_token is null
      and claim_expires_at is null
  ) then
    raise exception 'Permanent failure transition did not invalidate the live claim safely.';
  end if;

  if public.authorize_delivery_job(v_exhausted_id, v_exhausted_token) is not true then
    raise exception 'Live fifth-attempt fixture was not authorized.';
  end if;

  v_retry_result := public.retry_delivery_job(
    v_exhausted_id,
    v_exhausted_token,
    now() + interval '5 minutes',
    'provider_temporarily_unavailable'
  );

  if v_retry_result is not false then
    raise exception 'Fifth attempt unexpectedly requeued.';
  end if;

  if not exists (
    select 1
    from public.delivery_ledger
    where id = v_exhausted_id
      and state = 'failed'
      and attempt_count = 5
      and error_code = 'retry_exhausted'
      and failed_at is not null
      and claim_token is null
      and claim_expires_at is null
  ) then
    raise exception 'Fifth-attempt retry did not become a terminal retry_exhausted failure.';
  end if;
end;
$$;
reset role;

select jsonb_build_object(
  'delivery_terminal_transitions', 'pass',
  'sent_jobs', count(*) filter (where state = 'sent'),
  'failed_jobs', count(*) filter (where state = 'failed'),
  'retry_exhausted_jobs', count(*) filter (
    where state = 'failed' and error_code = 'retry_exhausted'
  )
) as delivery_reliability_terminal_behavior
from public.delivery_ledger;
