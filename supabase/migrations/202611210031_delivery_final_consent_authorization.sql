-- C252: serialize final provider authorization with current consent and identity.
-- The final RPC commits before external HTTP; its commit is the handoff boundary.
begin;

do $preflight$
begin
  if to_regprocedure('public.authorize_delivery_job(uuid,uuid)') is null
    or to_regprocedure('public.authorize_delivery_idempotency_window(uuid,uuid)') is null
    or obj_description(
      to_regprocedure('public.authorize_delivery_idempotency_window(uuid,uuid)'),
      'pg_proc'
    ) is distinct from 'deedlight:030:database-authoritative-provider-idempotency-horizon:v1'
    or to_regprocedure('public.begin_delivery_transport(uuid,uuid,text)') is null
    or to_regclass('public.delivery_provider_suppressions') is null
    or to_regclass('public.daily_reminder_preferences') is null
    or to_regclass('public.newsletter_preferences') is null
    or to_regclass('public.profiles') is null
    or to_regclass('public.weekly_goodness_features') is null
    or to_regclass('auth.users') is null
    or to_regclass('public.delivery_ledger') is null then
    raise exception 'Migration 031 requires the reviewed delivery authorization baseline through 030.';
  end if;
end;
$preflight$;

-- Both transport RPCs use the same order:
-- ledger -> provider-address advisory lock -> kind-specific consent ->
-- profile -> Auth user -> curated Weekly feature.
--
-- This replacement removes planner-dependent multi-table row-lock ordering
-- from migration 025 while preserving the recipient-bound and suppression gates.
create or replace function public.begin_delivery_transport(
  p_job_id uuid,
  p_claim_token uuid,
  p_expected_email text
)
returns timestamptz
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $transport$
declare
  v_job public.delivery_ledger%rowtype;
  v_daily public.daily_reminder_preferences%rowtype;
  v_weekly public.newsletter_preferences%rowtype;
  v_profile public.profiles%rowtype;
  v_user auth.users%rowtype;
  v_feature public.weekly_goodness_features%rowtype;
  v_email text;
  v_started_at timestamptz;
  v_now timestamptz;
  v_authorized boolean := false;
begin
  if p_job_id is null
    or p_claim_token is null
    or p_expected_email is null
    or char_length(p_expected_email) > 320
    or nullif(btrim(p_expected_email), '') is null then
    raise exception 'Invalid delivery transport authorization arguments.'
      using errcode = '22023';
  end if;
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'Delivery transport authorization requires READ COMMITTED isolation.'
      using errcode = '25000';
  end if;

  perform pg_catalog.set_config('lock_timeout', '5s', true);
  v_email := lower(btrim(p_expected_email));

  select * into v_job
  from public.delivery_ledger dl
  where dl.id = p_job_id
  for update;

  v_now := clock_timestamp();
  if not found
    or v_job.state <> 'claimed'
    or v_job.claim_token is distinct from p_claim_token
    or v_job.claim_expires_at is null
    or v_job.claim_expires_at <= v_now then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  if v_job.kind not in ('daily_reminder', 'weekly_newsletter') then
    raise exception 'Unsupported delivery kind.' using errcode = '22023';
  end if;

  -- Provider webhooks take this same per-address transaction lock.
  perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));

  if v_job.kind = 'daily_reminder' then
    select * into v_daily
    from public.daily_reminder_preferences drp
    where drp.user_id = v_job.user_id
    for share;

    if found and v_daily.daily_enabled then
      select * into v_profile
      from public.profiles p
      where p.user_id = v_job.user_id
      for share;

      if found and not v_profile.is_suspended then
        select * into v_user
        from auth.users u
        where u.id = v_job.user_id
        for share;

        if found
          and v_user.email_confirmed_at is not null
          and lower(btrim(v_user.email)) = v_email
          and exists (
            select 1 from pg_catalog.pg_timezone_names tz
            where tz.name = v_daily.timezone
          )
          and v_job.delivery_key =
            'daily:' || timezone(v_daily.timezone, v_job.scheduled_for)::date::text
          and v_job.scheduled_for = (
            (timezone(v_daily.timezone, v_job.scheduled_for)::date
              + v_daily.reminder_time) at time zone v_daily.timezone
          )
          and not exists (
            select 1 from public.delivery_provider_suppressions s
            where s.recipient_email = v_email
          ) then
          v_authorized := true;
        end if;
      end if;
    end if;

  else
    select * into v_weekly
    from public.newsletter_preferences np
    where np.user_id = v_job.user_id
    for share;

    if found and v_weekly.weekly_enabled and v_weekly.consented_at is not null then
      select * into v_profile
      from public.profiles p
      where p.user_id = v_job.user_id
      for share;

      if found and not v_profile.is_suspended then
        select * into v_user
        from auth.users u
        where u.id = v_job.user_id
        for share;

        if found
          and v_user.email_confirmed_at is not null
          and lower(btrim(v_user.email)) = v_email then
          select * into v_feature
          from public.weekly_goodness_features f
          where v_job.delivery_key = 'weekly:' || f.week_start::text
          for share;

          if found and not exists (
            select 1 from public.delivery_provider_suppressions s
            where s.recipient_email = v_email
          ) then
            v_authorized := true;
          end if;
        end if;
      end if;
    end if;
  end if;

  -- Recheck after all row/advisory lock waits, before persisting transport start.
  v_now := clock_timestamp();
  if v_job.claim_expires_at <= v_now then
    raise exception 'Claim expired during transport authorization.'
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
      raise exception 'Delivery claim is not authorized.' using errcode = '42501';
    end if;
    return null;
  end if;

  update public.delivery_ledger
  set transport_started_at = coalesce(transport_started_at, clock_timestamp()),
      updated_at = clock_timestamp()
  where id = v_job.id
    and state = 'claimed'
    and claim_token = p_claim_token
    and claim_expires_at > clock_timestamp()
  returning transport_started_at into v_started_at;

  if not found then
    raise exception 'Claim expired during transport authorization.'
      using errcode = '42501';
  end if;

  return v_started_at;
end;
$transport$;

revoke all privileges
on function public.begin_delivery_transport(uuid, uuid, text)
from public, anon, authenticated;
grant execute
on function public.begin_delivery_transport(uuid, uuid, text)
to service_role;

comment on function public.begin_delivery_transport(uuid, uuid, text)
is 'deedlight:031:ordered-recipient-bound-transport-start:v1';

-- Lock order: ledger -> provider-address advisory lock -> kind-specific
-- consent -> profile -> Auth user -> curated Weekly feature. The unlocked
-- email read only selects the advisory key; the locked Auth row is compared
-- with that snapshot before authorization can succeed.
--
-- READ COMMITTED is required so a waiter observes the committed revocation
-- that released a row lock. A bounded lock timeout fails closed before send.
create or replace function public.authorize_delivery_job(
  p_job_id uuid,
  p_claim_token uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $authorize$
declare
  v_job public.delivery_ledger%rowtype;
  v_daily public.daily_reminder_preferences%rowtype;
  v_weekly public.newsletter_preferences%rowtype;
  v_profile public.profiles%rowtype;
  v_user auth.users%rowtype;
  v_feature public.weekly_goodness_features%rowtype;
  v_email text;
  v_now timestamptz;
  v_authorized boolean := false;
begin
  if p_job_id is null or p_claim_token is null then
    raise exception 'A job ID and claim token are required.' using errcode = '22023';
  end if;
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'Final delivery authorization requires READ COMMITTED isolation.'
      using errcode = '25000';
  end if;

  perform pg_catalog.set_config('lock_timeout', '5s', true);

  select * into v_job
  from public.delivery_ledger dl
  where dl.id = p_job_id
  for update;

  v_now := clock_timestamp();
  if not found
    or v_job.state <> 'claimed'
    or v_job.claim_token is distinct from p_claim_token
    or v_job.claim_expires_at is null
    or v_job.claim_expires_at <= v_now then
    raise exception 'Delivery claim is not authorized.' using errcode = '42501';
  end if;

  if v_job.kind not in ('daily_reminder', 'weekly_newsletter') then
    raise exception 'Unsupported delivery kind.' using errcode = '22023';
  end if;

  -- This read is deliberately unlocked. It chooses the same advisory key used
  -- by the provider-webhook RPC; the locked Auth row below must still match it.
  select lower(btrim(u.email))
  into v_email
  from auth.users u
  where u.id = v_job.user_id;

  if found and nullif(v_email, '') is not null then
    -- Migration 025's provider-event RPC takes this exact per-address lock.
    perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));

    if v_job.kind = 'daily_reminder' then
      select * into v_daily
      from public.daily_reminder_preferences drp
      where drp.user_id = v_job.user_id
      for share;

      if found and v_daily.daily_enabled then
        select * into v_profile
        from public.profiles p
        where p.user_id = v_job.user_id
        for share;

        if found and not v_profile.is_suspended then
          select * into v_user
          from auth.users u
          where u.id = v_job.user_id
          for share;

          if found
            and v_user.email_confirmed_at is not null
            and lower(btrim(v_user.email)) = v_email
            and exists (
              select 1 from pg_catalog.pg_timezone_names tz
              where tz.name = v_daily.timezone
            )
            and v_job.delivery_key =
              'daily:' || timezone(v_daily.timezone, v_job.scheduled_for)::date::text
            and v_job.scheduled_for = (
              (timezone(v_daily.timezone, v_job.scheduled_for)::date
                + v_daily.reminder_time) at time zone v_daily.timezone
            )
            and not exists (
              select 1 from public.delivery_provider_suppressions s
              where s.recipient_email = v_email
            ) then
            v_authorized := true;
          end if;
        end if;
      end if;

    else
      select * into v_weekly
      from public.newsletter_preferences np
      where np.user_id = v_job.user_id
      for share;

      if found and v_weekly.weekly_enabled and v_weekly.consented_at is not null then
        select * into v_profile
        from public.profiles p
        where p.user_id = v_job.user_id
        for share;

        if found and not v_profile.is_suspended then
          select * into v_user
          from auth.users u
          where u.id = v_job.user_id
          for share;

          if found
            and v_user.email_confirmed_at is not null
            and lower(btrim(v_user.email)) = v_email then
            select * into v_feature
            from public.weekly_goodness_features f
            where v_job.delivery_key = 'weekly:' || f.week_start::text
            for share;

            if found and not exists (
              select 1 from public.delivery_provider_suppressions s
              where s.recipient_email = v_email
            ) then
              v_authorized := true;
            end if;
          end if;
        end if;
      end if;
    end if;
  end if;

  -- All potentially blocking locks have been acquired. Never use transaction-
  -- start now() for a lease that may have expired while waiting.
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
      raise exception 'Delivery claim is not authorized.' using errcode = '42501';
    end if;
    return false;
  end if;

  return true;
end;
$authorize$;

revoke all privileges
on function public.authorize_delivery_job(uuid, uuid)
from public, anon, authenticated;
grant execute
on function public.authorize_delivery_job(uuid, uuid)
to service_role;

comment on function public.authorize_delivery_job(uuid, uuid)
is 'deedlight:031:locked-final-consent-identity-and-suppression:v1';

-- The expected recipient is server-only and is never persisted. This binds the
-- final authorization to the exact address resolved before transport start.
-- The old two-argument RPC is removed so no caller can bypass identity binding.
drop function if exists public.authorize_delivery_idempotency_window(uuid, uuid);

create function public.authorize_delivery_idempotency_window(
  p_job_id uuid,
  p_claim_token uuid,
  p_expected_email text
)
returns text
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $idempotency$
declare
  v_job public.delivery_ledger%rowtype;
  v_current_email text;
  v_expected_email text;
  v_now timestamptz;
begin
  if p_job_id is null
    or p_claim_token is null
    or p_expected_email is null
    or char_length(p_expected_email) > 320
    or nullif(btrim(p_expected_email), '') is null then
    raise exception 'A job ID, claim token, and expected recipient are required.'
      using errcode = '22023';
  end if;

  v_expected_email := lower(btrim(p_expected_email));

  -- This call acquires and retains the ordered consent, profile, Auth,
  -- curated-feature and provider-suppression locks until this RPC commits.
  if public.authorize_delivery_job(p_job_id, p_claim_token) is not true then
    return 'cancelled';
  end if;

  select * into v_job
  from public.delivery_ledger dl
  where dl.id = p_job_id
  for update;

  v_now := clock_timestamp();
  if not found
    or v_job.state <> 'claimed'
    or v_job.claim_token is distinct from p_claim_token
    or v_job.claim_expires_at is null
    or v_job.claim_expires_at <= v_now
    or v_job.transport_started_at is null then
    raise exception 'Delivery claim is not authorized for provider transport.'
      using errcode = '42501';
  end if;

  -- authorize_delivery_job already holds this Auth row FOR SHARE. Re-reading
  -- it here binds the worker's resolved address to the still-locked identity.
  select lower(btrim(u.email))
  into v_current_email
  from auth.users u
  where u.id = v_job.user_id
  for share;

  v_now := clock_timestamp();
  if v_job.claim_expires_at <= v_now then
    raise exception 'Delivery claim expired during final provider authorization.'
      using errcode = '42501';
  end if;

  if not found or v_current_email is distinct from v_expected_email then
    update public.delivery_ledger
    set state = 'cancelled',
        cancelled_at = clock_timestamp(),
        claim_token = null,
        claim_expires_at = null,
        next_attempt_at = null,
        error_code = 'recipient_identity_changed',
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
$idempotency$;

revoke all privileges
on function public.authorize_delivery_idempotency_window(uuid, uuid, text)
from public, anon, authenticated;
grant execute
on function public.authorize_delivery_idempotency_window(uuid, uuid, text)
to service_role;

comment on function public.authorize_delivery_idempotency_window(uuid, uuid, text)
is 'deedlight:031:final-recipient-bound-provider-handoff:v1';

-- Serialization boundary: the successful commit of this final RPC is the
-- provider-handoff authorization point. If revocation obtains a protected row
-- lock first, this RPC waits, observes the revocation and cancels. If this RPC
-- obtains the locks first, revocation waits until this transaction commits.
-- After that commit, a later revocation cannot recall an already-authorized
-- external request. The Worker starts HTTP immediately after this RPC; no DB
-- transaction is held open around provider IO. A later retry must reauthorize
-- current consent and reuses the existing stable provider idempotency key.

notify pgrst, 'reload schema';
commit;
