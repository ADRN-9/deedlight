-- Reconcile email.suppressed lifecycle events with the migration-032 provider-state projection.
-- A late generic lifecycle event cannot restore a manual suppression removed later by Resend.
begin;

do $migration_033_preflight$
begin
  if to_regclass('public.delivery_provider_suppressions') is null
    or to_regclass('public.delivery_provider_suppression_state') is null
    or to_regprocedure('public._record_delivery_provider_lifecycle_event_fingerprinted_impl(text,text,text,text,timestamptz,text,text,text,text)') is null then
    raise exception 'Migration 033 requires migration 032 suppression state and the private migration-029 lifecycle implementation.';
  end if;
end;
$migration_033_preflight$;

-- Preserve migration 029's fingerprint gate and legacy replay-only behavior.
-- The private implementation takes the shared per-recipient advisory lock;
-- that transaction-scoped lock remains held through this reconciliation.
create or replace function public.record_delivery_provider_lifecycle_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_provider_created_at timestamptz,
  p_bounce_type text,
  p_failure_class text,
  p_suppression_reason text,
  p_payload_fingerprint text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $cross_stream$
declare
  v_existing public.delivery_provider_events%rowtype;
  v_email text;
  v_result boolean;
begin
  if p_payload_fingerprint is null then
    if p_event_id is null or char_length(p_event_id) not between 1 and 255
      or p_provider_email_id is null or char_length(p_provider_email_id) not between 1 and 255
      or p_recipient_email is null or char_length(p_recipient_email) > 320 then
      raise exception 'A valid event ID, provider email ID and recipient are required for historical replay.'
        using errcode = '22023';
    end if;

    v_email := lower(btrim(p_recipient_email));
    if char_length(v_email) not between 3 and 320 then
      raise exception 'Invalid delivery provider recipient.' using errcode = '22023';
    end if;

    -- Keep the canonical implementation's lock order for fingerprint-less replays.
    perform pg_catalog.pg_advisory_xact_lock(20261119, hashtext(v_email));
    perform pg_catalog.pg_advisory_xact_lock(20261126, hashtext(p_provider_email_id));

    select e.* into v_existing
    from public.delivery_provider_events e
    where e.event_id = p_event_id
    for update;

    if not found then
      raise exception 'Fingerprint-less provider events cannot be inserted; use the fingerprinted canonical RPC.'
        using errcode = '42501';
    end if;
  end if;

  v_result := public._record_delivery_provider_lifecycle_event_fingerprinted_impl(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    p_recipient_email,
    p_provider_created_at,
    p_bounce_type,
    p_failure_class,
    p_suppression_reason,
    p_payload_fingerprint
  );

  if v_result is true
    and p_event_type = 'email.suppressed'
    and p_suppression_reason = 'provider_suppressed' then
    v_email := lower(btrim(p_recipient_email));

    -- A strictly newer manual removal wins across the email and suppression-list
    -- event families. Equal timestamps remain blocked as ambiguous.
    if exists (
      select 1
      from public.delivery_provider_suppression_state s
      where s.recipient_email = v_email
        and s.origin = 'manual'
        and s.is_active = false
        and s.provider_created_at > p_provider_created_at
    ) then
      delete from public.delivery_provider_suppressions
      where recipient_email = v_email
        and reason = 'provider_suppressed';
    end if;
  end if;

  return v_result;
end;
$cross_stream$;

revoke all privileges
on function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text, text, text
)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text, text, text
)
to service_role;

comment on function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text, text, text
)
is 'deedlight:033:cross-stream-suppression-order:v1';

notify pgrst, 'reload schema';
commit;
