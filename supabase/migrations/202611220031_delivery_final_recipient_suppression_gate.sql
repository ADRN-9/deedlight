-- Revalidate the exact recipient, current consent and provider suppression at the final send boundary.
-- Migration 031 replaces migration 030's last pre-send authorization RPC.
begin;

do $$
begin
  if to_regprocedure('public.authorize_delivery_idempotency_window(uuid,uuid)') is null
    or to_regprocedure('public.begin_delivery_transport(uuid,uuid,text)') is null
    or to_regclass('public.delivery_provider_suppressions') is null
    or to_regclass('public.daily_reminder_preferences') is null
    or to_regclass('public.newsletter_preferences') is null
    or to_regclass('public.profiles') is null
    or to_regclass('auth.users') is null then
    raise exception 'Migration 031 requires the reviewed delivery, recipient and provider-suppression baseline through migration 030.';
  end if;
end;
$$;

drop function public.authorize_delivery_idempotency_window(uuid, uuid);

create function public.authorize_delivery_idempotency_window(
  p_job_id uuid,
  p_claim_token uuid,
  p_expected_email text
)
returns text
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $final_gate$
declare
  v_job public.delivery_ledger%rowtype;
  v_email text;
  v_authorized boolean := false;
  v_now timestamptz;
begin
  if p_job_id is null or p_claim_token is null
    or p_expected_email is null
    or char_length(p_expected_email) > 320
    or nullif(btrim(p_expected_email), '') is null then
    raise exception 'A job ID, claim token and expected recipient are required.'
      using errcode = '22023';
  end if;

  v_email := lower(btrim(p_expected_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
    raise exception 'Invalid expected delivery recipient.' using errcode = '22023';
  end if;

  select * into v_job
  from public.delivery_ledger dl
  where dl.id = p_job_id
  for update;

  v_now := clock_timestamp();
  if not found or v_job.state <> 'claimed'
    or v_job.claim_token is distinct from p_claim_token
    or v_job.claim_expires_at is null
    or v_job.claim_expires_at <= v_now
    or v_job.transport_started_at is null then
    raise exception 'Delivery claim is not authorized for provider transport.'
      using errcode = '42501';
  end if;

  -- Serialize the final check with bounce/complaint/suppression intake.
  -- A suppression committed before this lock is observed; a concurrent event
  -- must wait until this final authorization transaction completes.
  perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));

  if v_job.kind = 'daily_reminder' then
    perform 1
    from public.daily_reminder_preferences drp
    join public.profiles p
      on p.user_id = drp.user_id
     and p.is_suspended = false
    join auth.users u
      on u.id = drp.user_id
     and u.email_confirmed_at is not null
     and lower(btrim(u.email)) = v_email
    join pg_catalog.pg_timezone_names tz
      on tz.name = drp.timezone
    where drp.user_id = v_job.user_id
      and drp.daily_enabled = true
      and v_job.delivery_key =
        'daily:' || timezone(drp.timezone, v_job.scheduled_for)::date::text
      and v_job.scheduled_for = (
        (timezone(drp.timezone, v_job.scheduled_for)::date
          + drp.reminder_time) at time zone drp.timezone
      )
      and not exists (
        select 1
        from public.delivery_provider_suppressions s
        where s.recipient_email = v_email
      )
    for share of drp, p, u;
    v_authorized := found;
  elsif v_job.kind = 'weekly_newsletter' then
    perform 1
    from public.newsletter_preferences np
    join public.profiles p
      on p.user_id = np.user_id
     and p.is_suspended = false
    join auth.users u
      on u.id = np.user_id
     and u.email_confirmed_at is not null
     and lower(btrim(u.email)) = v_email
    join public.weekly_goodness_features f
      on v_job.delivery_key = 'weekly:' || f.week_start::text
    where np.user_id = v_job.user_id
      and np.weekly_enabled = true
      and np.consented_at is not null
      and not exists (
        select 1
        from public.delivery_provider_suppressions s
        where s.recipient_email = v_email
      )
    for share of np, p, u, f;
    v_authorized := found;
  else
    raise exception 'Unsupported delivery kind.' using errcode = '22023';
  end if;

  -- Preference, profile and Auth rows remain locked through this transaction.
  -- Recheck the finite claim lease after those potentially blocking reads.
  v_now := clock_timestamp();
  if v_job.claim_expires_at <= v_now then
    raise exception 'Delivery claim expired during final authorization.'
      using errcode = '42501';
  end if;

  if not v_authorized then
    update public.delivery_ledger
    set state = 'cancelled',
        cancelled_at = clock_timestamp(),
        claim_token = null,
        claim_expires_at = null,
        next_attempt_at = null,
        error_code = 'authorization_revoked',
        updated_at = clock_timestamp()
    where id = v_job.id
      and state = 'claimed'
      and claim_token = p_claim_token
      and claim_expires_at > clock_timestamp();

    if not found then
      raise exception 'Delivery claim is not authorized for provider transport.'
        using errcode = '42501';
    end if;
    return 'cancelled';
  end if;

  if v_job.transport_started_at + interval '23 hours' <= v_now + interval '30 seconds' then
    update public.delivery_ledger
    set state = 'failed',
        failed_at = clock_timestamp(),
        claim_token = null,
        claim_expires_at = null,
        next_attempt_at = null,
        error_code = 'provider_idempotency_window_expired',
        updated_at = clock_timestamp()
    where id = v_job.id
      and state = 'claimed'
      and claim_token = p_claim_token
      and claim_expires_at > clock_timestamp();

    if not found then
      raise exception 'Delivery claim is not authorized for provider transport.'
        using errcode = '42501';
    end if;
    return 'expired';
  end if;

  return 'authorized';
end;
$final_gate$;

revoke all privileges
on function public.authorize_delivery_idempotency_window(uuid, uuid, text)
from public, anon, authenticated;
grant execute
on function public.authorize_delivery_idempotency_window(uuid, uuid, text)
to service_role;
comment on function public.authorize_delivery_idempotency_window(uuid, uuid, text)
is 'deedlight:031:final-recipient-consent-and-suppression-gate:v1';

notify pgrst, 'reload schema';
commit;
