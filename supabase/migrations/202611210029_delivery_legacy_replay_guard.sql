-- Restrict fingerprint-less provider RPCs to existing historical replays.
-- Migration 027 remains immutable; new events require the fingerprinted 9-argument RPC.
begin;

do $c226$
declare
  v_oid oid; v_source text; v_hash text; v_crypto_schema text;
  v_definer boolean; v_config text[]; v_language text; v_comment text;
begin
  if to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)') is null
    or to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)') is null
    or to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text)') is null
    or to_regprocedure('public.record_delivery_provider_event(text,text,text,text,text)') is null then
    raise exception 'Migration 029 requires the reviewed provider lifecycle and legacy RPC overloads from migration 027.';
  end if;
  if to_regprocedure('public._record_delivery_provider_lifecycle_event_fingerprinted_impl(text,text,text,text,timestamptz,text,text,text,text)') is not null then
    raise exception 'Migration 029 refuses an existing private implementation with an unknown origin.';
  end if;
  v_oid := to_regprocedure('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)');
  select p.prosrc,p.prosecdef,p.proconfig,l.lanname,obj_description(p.oid,'pg_proc')
  into v_source,v_definer,v_config,v_language,v_comment
  from pg_catalog.pg_proc p join pg_catalog.pg_language l on l.oid=p.prolang where p.oid=v_oid;
  if v_source is null or v_language <> 'plpgsql' or v_definer is distinct from true
    or v_config is distinct from array['search_path=public, auth, pg_temp']::text[]
    or v_comment is distinct from 'deedlight:027:provider-lifecycle-integrity-and-suppression-reasons:v1' then
    raise exception 'Migration 029 refuses an unrecognized migration-027 provider lifecycle implementation.';
  end if;
  select n.nspname into v_crypto_schema
  from pg_catalog.pg_extension e join pg_catalog.pg_namespace n on n.oid=e.extnamespace
  where e.extname='pgcrypto';
  if v_crypto_schema is null then
    raise exception 'Migration 029 requires pgcrypto to verify the migration-027 implementation identity.';
  end if;
  execute format('select encode(%I.digest(convert_to($1, ''UTF8''), ''sha256''), ''hex'')',v_crypto_schema)
  into v_hash using v_source;
  if v_hash is distinct from '8dbfc65b93677f9928114561d372dad69f16c9c746dadf80551c662161ba3ed5' then
    raise exception 'Migration 029 refuses an unrecognized migration-027 provider lifecycle implementation.';
  end if;
end;
$c226$;

-- Keep the reviewed 027 lifecycle implementation intact under a private name.
-- The public canonical RPC below becomes the only entry point to this implementation.
alter function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text, text, text
) rename to _record_delivery_provider_lifecycle_event_fingerprinted_impl;

revoke all privileges
on function public._record_delivery_provider_lifecycle_event_fingerprinted_impl(
  text, text, text, text, timestamptz, text, text, text, text
)
from public, anon, authenticated, service_role;

comment on function public._record_delivery_provider_lifecycle_event_fingerprinted_impl(
  text, text, text, text, timestamptz, text, text, text, text
)
is 'Private migration-027 lifecycle implementation; invoke only through the fingerprint-enforcing canonical RPC.';

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
as $canonical$
declare
  v_existing public.delivery_provider_events%rowtype;
  v_email text;
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

    -- Match the canonical implementation's lock order before inspecting the
    -- event row. This serializes NULL-digest replays against concurrent inserts.
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

    -- A stored NULL digest is the historical compatibility case. A stored
    -- non-NULL digest must take the implementation's conflict/anomaly path:
    -- the legacy caller cannot prove an exact replay without the raw-body hash.
  end if;

  return public._record_delivery_provider_lifecycle_event_fingerprinted_impl(
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
end;
$canonical$;

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
is 'deedlight:029:fingerprint-required-for-new-provider-events:v1';

-- Reassert the service-only legacy RPC boundary. Their existing wrappers
-- pass NULL to the canonical entry point and therefore cannot create rows.
revoke all privileges
on function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text, text
)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text, text
)
to service_role;

revoke all privileges
on function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text
)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_lifecycle_event(
  text, text, text, text, timestamptz, text, text
)
to service_role;

revoke all privileges
on function public.record_delivery_provider_event(text, text, text, text, text)
from public, anon, authenticated;
grant execute
on function public.record_delivery_provider_event(text, text, text, text, text)
to service_role;

notify pgrst, 'reload schema';
commit;
