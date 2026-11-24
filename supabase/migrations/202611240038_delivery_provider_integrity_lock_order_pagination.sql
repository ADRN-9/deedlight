-- Forward-only hardening for provider event identity serialization and paginated admin review.
-- Migrations 036 and 037 remain immutable. Unexpected source/ACL/configuration drift aborts atomically.
begin;

do $migration_038_preflight$
declare
  v_crypto_schema text;
  v_expected record;
  v_oid oid;
  v_source text;
  v_source_hash text;
  v_security_definer boolean;
  v_config text[];
begin
  if to_regclass('public.delivery_provider_integrity_cases') is null
    or to_regclass('public.delivery_provider_integrity_conflict_evidence') is null
    or to_regclass('public.delivery_provider_integrity_conflict_history') is null
    or to_regprocedure('public.is_admin()') is null then
    raise exception 'Migration 038 requires the complete migration-037 provider-integrity and administrator contract.';
  end if;

  select n.nspname into v_crypto_schema
  from pg_catalog.pg_extension e
  join pg_catalog.pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';

  if v_crypto_schema is null then
    raise exception 'Migration 038 requires pgcrypto for exact provider RPC source attestation.';
  end if;

  if to_regprocedure('public.admin_list_delivery_provider_integrity_conflicts_page(text,integer,timestamptz,bigint)') is not null
    or to_regprocedure('public.admin_get_delivery_provider_integrity_conflict(bigint)') is not null
    or to_regprocedure('public.admin_list_delivery_provider_integrity_evidence_page(bigint,integer,timestamptz,bigint)') is not null
    or to_regprocedure('public.admin_list_delivery_provider_integrity_history_page(bigint,integer,timestamptz,bigint)') is not null
    or to_regclass('public.delivery_provider_integrity_cases_state_cursor_idx') is not null
    or to_regclass('public.delivery_provider_integrity_conflict_history_reopened_cursor_idx') is not null then
    raise exception 'Migration 038 refuses pre-existing pagination objects with an unknown origin.';
  end if;

  for v_expected in
    select * from (values
      ('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)', '4b8c7b9c0ea7af1cea5e3d34ed3d1a21cbd5c17958a4d89f8c857cfa38f7581b', 'search_path=public, auth, pg_temp', 'service_role'),
      ('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)', '9be2593c7187516b0ca4a413f9443b02fd8f4ea9b02f539f1b5b504eb53eb694', 'search_path=public, auth, pg_temp', 'service_role'),
      ('public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text)', 'abca9b6c4ccd2e51dc7b0523d18b4e6931a082baa3b260fe308b78e0e7563536', 'search_path=public, auth, pg_temp', 'service_role'),
      ('public.record_delivery_provider_event(text,text,text,text,text)', '5896bffd634d825be05a5e8bdf78c6b0bae2ded24591b283fea764a74cb5343b', 'search_path=public, auth, pg_temp', 'service_role'),
      ('public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)', '5e3eb059c12dd9caa50a060447fd09d3afc217142bd58e94d1afd5a1cbbb62a6', 'search_path=public, auth, pg_temp', 'service_role'),
      ('public._record_delivery_provider_integrity_conflict(text,text,text,text,text,text,text,timestamptz,text,text,text,text,text,timestamptz,text,text,text)', 'efc5a85b3e0ca1ee32f38e12f5f2538a135ee08203f79d1c9d2e57a4d0950871', 'search_path=public, auth, pg_temp', 'private'),
      ('public._record_delivery_provider_lifecycle_event_pre037_impl(text,text,text,text,timestamptz,text,text,text,text)', '68bf0948c041e70670499811334bee6fc4546254d0597d38b880e8aad18c7241', 'search_path=public, auth, pg_temp', 'private'),
      ('public._record_delivery_provider_suppression_event_pre037_impl(text,text,text,text,text,text,timestamptz,timestamptz,text)', 'd67c0f2da59cd87e769938a9c86878791080a2e9597409113796be078e87e64a', 'search_path=public, auth, pg_temp', 'private'),
      ('public._deny_delivery_provider_integrity_audit_mutation()', '2dff07aeeb597e3d8e8bca99108a4df8d1538161ab0b0e4c34e47d71790d96c9', 'search_path=pg_catalog', 'private'),
      ('public.admin_list_delivery_provider_integrity_conflicts(text,integer)', 'c77643294b78d01bdad25cce4cfc0e7bac10f7d12f9898c2b169fa012add6bc0', 'search_path=public, auth, pg_temp', 'authenticated'),
      ('public.admin_list_delivery_provider_integrity_evidence(bigint,integer)', '72609677508aa59960571a22c39b4b6cbbb0bcf3106339b995b5133a863d4b3f', 'search_path=public, auth, pg_temp', 'authenticated'),
      ('public.admin_list_delivery_provider_integrity_history(bigint,integer)', 'c818efdd81bc98ad96adb7439ee70024cb101fbfcaa9cfe557bbf3c2dfe233a4', 'search_path=public, auth, pg_temp', 'authenticated'),
      ('public.admin_resolve_delivery_provider_integrity_conflict(bigint,text)', '53de2fc64a9fa634efe33e18b7f639a474d9f359a2c57066b9bac760aa9b16e1', 'search_path=public, auth, pg_temp', 'authenticated')
    ) as expected(signature, source_sha256, expected_search_path, access_role)
  loop
    v_oid := to_regprocedure(v_expected.signature);
    if v_oid is null then
      raise exception 'Migration 038 requires reviewed function signature %.', v_expected.signature;
    end if;

    select p.prosrc, p.prosecdef, p.proconfig
      into v_source, v_security_definer, v_config
    from pg_catalog.pg_proc p
    where p.oid = v_oid;

    if v_security_definer is distinct from true
      or v_config is distinct from array[v_expected.expected_search_path]::text[] then
      raise exception 'Migration 038 rejected SECURITY DEFINER/search_path drift in %.', v_expected.signature;
    end if;

    execute format(
      'select encode(%I.digest(convert_to($1, ''UTF8''), ''sha256''), ''hex'')',
      v_crypto_schema
    ) into v_source_hash using v_source;

    if v_source_hash is distinct from v_expected.source_sha256 then
      raise exception 'Migration 038 rejected unreviewed function source for %.', v_expected.signature;
    end if;

    if v_expected.access_role = 'service_role' then
      if has_function_privilege('anon', v_oid, 'EXECUTE')
        or has_function_privilege('authenticated', v_oid, 'EXECUTE')
        or not has_function_privilege('service_role', v_oid, 'EXECUTE') then
        raise exception 'Migration 038 rejected non-service provider RPC grants for %.', v_expected.signature;
      end if;
    elsif v_expected.access_role = 'authenticated' then
      if has_function_privilege('anon', v_oid, 'EXECUTE')
        or has_function_privilege('service_role', v_oid, 'EXECUTE')
        or not has_function_privilege('authenticated', v_oid, 'EXECUTE') then
        raise exception 'Migration 038 rejected administrator RPC grants for %.', v_expected.signature;
      end if;
    elsif v_expected.access_role = 'private' then
      if has_function_privilege('anon', v_oid, 'EXECUTE')
        or has_function_privilege('authenticated', v_oid, 'EXECUTE')
        or has_function_privilege('service_role', v_oid, 'EXECUTE') then
        raise exception 'Migration 038 rejected private helper grants for %.', v_expected.signature;
      end if;
    else
      raise exception 'Migration 038 has an invalid preflight access contract.';
    end if;
  end loop;

  if not (select relrowsecurity from pg_catalog.pg_class where oid='public.delivery_provider_integrity_cases'::regclass)
    or not (select relrowsecurity from pg_catalog.pg_class where oid='public.delivery_provider_integrity_conflict_evidence'::regclass)
    or not (select relrowsecurity from pg_catalog.pg_class where oid='public.delivery_provider_integrity_conflict_history'::regclass)
    or has_table_privilege('anon','public.delivery_provider_integrity_cases','SELECT')
    or has_table_privilege('authenticated','public.delivery_provider_integrity_cases','SELECT')
    or has_table_privilege('service_role','public.delivery_provider_integrity_cases','SELECT')
    or has_table_privilege('anon','public.delivery_provider_integrity_conflict_evidence','SELECT')
    or has_table_privilege('authenticated','public.delivery_provider_integrity_conflict_evidence','SELECT')
    or has_table_privilege('service_role','public.delivery_provider_integrity_conflict_evidence','SELECT')
    or has_table_privilege('anon','public.delivery_provider_integrity_conflict_history','SELECT')
    or has_table_privilege('authenticated','public.delivery_provider_integrity_conflict_history','SELECT')
    or has_table_privilege('service_role','public.delivery_provider_integrity_conflict_history','SELECT') then
    raise exception 'Migration 038 rejected provider-integrity table privacy drift.';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_trigger
    where tgrelid='public.delivery_provider_integrity_conflict_evidence'::regclass
      and tgname='delivery_provider_integrity_conflict_evidence_immutable'
      and tgfoid=to_regprocedure('public._deny_delivery_provider_integrity_audit_mutation()')
      and not tgisinternal
  ) or not exists (
    select 1 from pg_catalog.pg_trigger
    where tgrelid='public.delivery_provider_integrity_conflict_history'::regclass
      and tgname='delivery_provider_integrity_conflict_history_immutable'
      and tgfoid=to_regprocedure('public._deny_delivery_provider_integrity_audit_mutation()')
      and not tgisinternal
  ) then
    raise exception 'Migration 038 requires both append-only audit triggers.';
  end if;
end;
$migration_038_preflight$;

-- Indexes match the keyset order and make the latest reopening independently discoverable.
create index delivery_provider_integrity_cases_state_cursor_idx
  on public.delivery_provider_integrity_cases (state, last_detected_at desc, conflict_id desc);

create index delivery_provider_integrity_conflict_history_reopened_cursor_idx
  on public.delivery_provider_integrity_conflict_history (conflict_id, created_at desc, history_id desc)
  where action = 'reopened';

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
as $lifecycle_037$
declare
  v_email text;
  v_existing public.delivery_provider_events%rowtype;
  v_related public.delivery_provider_events%rowtype;
  v_anomaly public.delivery_provider_integrity_anomalies%rowtype;
  v_existing_lifecycle public.delivery_provider_lifecycle%rowtype;
  v_had_lifecycle boolean := false;
  v_result boolean;
begin
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_event_type is null
    or p_event_type not in (
      'email.sent', 'email.delivered', 'email.delivery_delayed', 'email.bounced',
      'email.complained', 'email.suppressed', 'email.failed'
    )
    or p_provider_email_id is null
    or char_length(p_provider_email_id) not between 1 and 255
    or p_recipient_email is null
    or char_length(p_recipient_email) > 320
    or p_provider_created_at is null
    or (p_payload_fingerprint is not null and p_payload_fingerprint !~ '^[0-9a-f]{64}$') then
    raise exception 'Invalid delivery provider lifecycle event.' using errcode = '22023';
  end if;

  v_email := lower(btrim(p_recipient_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Invalid delivery provider recipient.' using errcode = '22023';
  end if;

  if p_event_type = 'email.bounced' then
    if p_bounce_type is null or p_bounce_type not in ('Permanent', 'Transient', 'Unknown') then
      raise exception 'Invalid delivery bounce classification.' using errcode = '22023';
    end if;
  elsif p_bounce_type is not null then
    raise exception 'Bounce classification is only valid for bounced events.' using errcode = '22023';
  end if;

  if p_event_type = 'email.failed' then
    if p_failure_class is null or p_failure_class not in (
      'invalid_recipient', 'provider_authentication', 'domain_verification',
      'quota_exceeded', 'content_rejected', 'unknown'
    ) then
      raise exception 'Invalid normalized provider failure classification.' using errcode = '22023';
    end if;
  elsif p_failure_class is not null then
    raise exception 'Failure classification is only valid for failed events.' using errcode = '22023';
  end if;

  if p_event_type = 'email.suppressed' then
    if p_suppression_reason is null or p_suppression_reason not in (
      'previous_bounce', 'previous_complaint', 'provider_suppressed'
    ) then
      raise exception 'Invalid normalized provider suppression reason.' using errcode = '22023';
    end if;
  elsif p_suppression_reason is not null then
    raise exception 'Suppression reason is only valid for suppressed events.' using errcode = '22023';
  end if;

  -- Global order: event identity, normalized recipient, then provider correlation.
  perform pg_catalog.pg_advisory_xact_lock(20261118, pg_catalog.hashtext(p_event_id));
  perform pg_catalog.pg_advisory_xact_lock(20261119, pg_catalog.hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261126, pg_catalog.hashtext(p_provider_email_id));

  select e.* into v_existing
  from public.delivery_provider_events e
  where e.event_id = p_event_id
  for update;

  select l.* into v_existing_lifecycle
  from public.delivery_provider_lifecycle l
  where l.provider_email_id = p_provider_email_id
  for update;
  v_had_lifecycle := found;

  -- Migration 027 used to raise and roll back on a provider-email-ID recipient
  -- collision. Persist the rejected attempt as private evidence instead, return
  -- NULL (the webhook route maps it to retryable HTTP 503), and keep the original
  -- event/suppression state untouched.
  select e.* into v_related
  from public.delivery_provider_events e
  where e.provider_email_id = p_provider_email_id
    and e.recipient_email <> v_email
  order by e.received_at, e.event_id
  limit 1
  for update;

  if found then
    perform public._record_delivery_provider_integrity_conflict(
      v_email, p_event_id, v_related.event_id, 'provider_email_recipient_conflict',
      p_event_type, p_provider_email_id, null, p_provider_created_at,
      p_bounce_type, p_failure_class, p_suppression_reason, null, null, null,
      p_payload_fingerprint, v_related.event_id, v_related.recipient_email
    );

    update public.delivery_provider_lifecycle
    set status = 'integrity_anomaly',
        status_rank = 80,
        failure_class = null,
        updated_at = clock_timestamp()
    where provider_email_id = p_provider_email_id;

    return null;
  end if;

  v_result := public._record_delivery_provider_lifecycle_event_pre037_impl(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    v_email,
    p_provider_created_at,
    p_bounce_type,
    p_failure_class,
    p_suppression_reason,
    p_payload_fingerprint
  );

  if v_result is null then
    select a.* into v_anomaly
    from public.delivery_provider_integrity_anomalies a
    where a.event_id = p_event_id
      and a.anomaly_type in ('duplicate_event_id_conflict', 'contradictory_terminal_outcome')
    order by a.detected_at desc
    limit 1;

    if not found then
      raise exception 'Provider lifecycle conflict was not durably classified.' using errcode = 'XX000';
    end if;

    select e.* into v_existing
    from public.delivery_provider_events e
    where e.event_id = p_event_id
    for update;

    if v_anomaly.anomaly_type = 'duplicate_event_id_conflict' then
      if not found then
        raise exception 'Conflicting duplicate provider event has no canonical event row.' using errcode = 'XX000';
      end if;
      perform public._record_delivery_provider_integrity_conflict(
        v_email, p_event_id, null, v_anomaly.anomaly_type,
        p_event_type, p_provider_email_id, null, p_provider_created_at,
        p_bounce_type, p_failure_class, p_suppression_reason, null, null, null,
        p_payload_fingerprint, v_existing.event_id, v_existing.recipient_email
      );

    else
      select e.* into v_related
      from public.delivery_provider_events e
      where e.event_id = v_anomaly.related_event_id
      for update;
      if not found then
        raise exception 'Contradictory provider event has no related canonical event.' using errcode = 'XX000';
      end if;
      perform public._record_delivery_provider_integrity_conflict(
        v_email, p_event_id, v_anomaly.related_event_id, v_anomaly.anomaly_type,
        p_event_type, p_provider_email_id, null, p_provider_created_at,
        p_bounce_type, p_failure_class, p_suppression_reason, null, null, null,
        p_payload_fingerprint, v_related.event_id, v_related.recipient_email
      );

      -- The prior implementation projected the conflicting terminal event over
      -- the canonical one. Keep only the integrity status overlay and restore all
      -- previously authoritative event/timestamp/classification fields.
      if v_had_lifecycle then
        update public.delivery_provider_lifecycle
        set status = 'integrity_anomaly',
            status_rank = 80,
            provider_created_at = v_existing_lifecycle.provider_created_at,
            received_at = v_existing_lifecycle.received_at,
            event_id = v_existing_lifecycle.event_id,
            failure_class = null,
            updated_at = clock_timestamp()
        where provider_email_id = p_provider_email_id;
      end if;
    end if;
  end if;

  return v_result;
end;
$lifecycle_037$;

create or replace function public.record_delivery_provider_lifecycle_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_provider_created_at timestamptz,
  p_bounce_type text default null,
  p_failure_class text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $legacy_037$
declare
  v_email text;
  v_existing_provider_created_at timestamptz;
  v_suppression_reason text;
begin
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_provider_email_id is null or char_length(p_provider_email_id) not between 1 and 255
    or p_recipient_email is null or char_length(p_recipient_email) > 320 then
    raise exception 'Invalid legacy delivery provider event identity.' using errcode = '22023';
  end if;

  v_email := lower(btrim(p_recipient_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
    raise exception 'Invalid legacy delivery provider recipient.' using errcode = '22023';
  end if;

  -- The legacy timestamp lookup must happen only after the global event lock.
  perform pg_catalog.pg_advisory_xact_lock(20261118, pg_catalog.hashtext(p_event_id));
  perform pg_catalog.pg_advisory_xact_lock(20261119, pg_catalog.hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261126, pg_catalog.hashtext(p_provider_email_id));

  select e.provider_created_at into v_existing_provider_created_at
  from public.delivery_provider_events e
  where e.event_id = p_event_id
  for update;

  if p_event_type = 'email.suppressed' then
    v_suppression_reason := 'provider_suppressed';
  end if;

  return public.record_delivery_provider_lifecycle_event(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    p_recipient_email,
    coalesce(v_existing_provider_created_at, p_provider_created_at, clock_timestamp()),
    p_bounce_type,
    p_failure_class,
    v_suppression_reason,
    null
  );
end;
$legacy_037$; then
    raise exception 'Invalid legacy delivery provider recipient.' using errcode = '22023';
  end if;

  -- The legacy timestamp lookup must happen only after the global event lock.
  perform pg_catalog.pg_advisory_xact_lock(20261118, pg_catalog.hashtext(p_event_id));
  perform pg_catalog.pg_advisory_xact_lock(20261119, pg_catalog.hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261126, pg_catalog.hashtext(p_provider_email_id));

  select e.provider_created_at into v_existing_provider_created_at
  from public.delivery_provider_events e
  where e.event_id = p_event_id
  for update;

  if p_event_type = 'email.suppressed' then
    v_suppression_reason := 'provider_suppressed';
  end if;

  return public.record_delivery_provider_lifecycle_event(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    p_recipient_email,
    coalesce(v_existing_provider_created_at, p_provider_created_at, clock_timestamp()),
    p_bounce_type,
    p_failure_class,
    v_suppression_reason,
    null
  );
end;
$legacy_037$;

create or replace function public.record_delivery_provider_lifecycle_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_provider_created_at timestamptz,
  p_bounce_type text,
  p_failure_class text,
  p_suppression_reason text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $compat_038$
declare
  v_email text;
begin
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_provider_email_id is null or char_length(p_provider_email_id) not between 1 and 255
    or p_recipient_email is null or char_length(p_recipient_email) > 320 then
    raise exception 'Invalid legacy delivery provider event identity.' using errcode = '22023';
  end if;

  v_email := lower(btrim(p_recipient_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
    raise exception 'Invalid legacy delivery provider recipient.' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(20261118, pg_catalog.hashtext(p_event_id));
  perform pg_catalog.pg_advisory_xact_lock(20261119, pg_catalog.hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261126, pg_catalog.hashtext(p_provider_email_id));

  return public.record_delivery_provider_lifecycle_event(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    v_email,
    p_provider_created_at,
    p_bounce_type,
    p_failure_class,
    p_suppression_reason,
    null
  );
end;
$compat_038$;

create or replace function public.record_delivery_provider_event(
  p_event_id text,
  p_event_type text,
  p_provider_email_id text,
  p_recipient_email text,
  p_bounce_type text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $legacy_038$
declare
  v_email text;
begin
  if p_event_type not in ('email.bounced', 'email.complained', 'email.suppressed') then
    raise exception 'Unsupported legacy provider event type.' using errcode = '22023';
  end if;
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_provider_email_id is null or char_length(p_provider_email_id) not between 1 and 255
    or p_recipient_email is null or char_length(p_recipient_email) > 320 then
    raise exception 'Invalid legacy delivery provider event identity.' using errcode = '22023';
  end if;

  v_email := lower(btrim(p_recipient_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
    raise exception 'Invalid legacy delivery provider recipient.' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(20261118, pg_catalog.hashtext(p_event_id));
  perform pg_catalog.pg_advisory_xact_lock(20261119, pg_catalog.hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261126, pg_catalog.hashtext(p_provider_email_id));

  return public.record_delivery_provider_lifecycle_event(
    p_event_id,
    p_event_type,
    p_provider_email_id,
    v_email,
    clock_timestamp(),
    p_bounce_type,
    null
  );
end;
$legacy_038$;

create or replace function public.record_delivery_provider_suppression_event(
  p_event_id text,
  p_event_type text,
  p_provider_suppression_id text,
  p_recipient_email text,
  p_suppression_origin text,
  p_suppression_source_id text,
  p_suppression_created_at timestamptz,
  p_provider_created_at timestamptz,
  p_payload_fingerprint text
)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $suppression_037$
declare
  v_email text;
  v_related public.delivery_provider_events%rowtype;
  v_existing public.delivery_provider_events%rowtype;
  v_anomaly public.delivery_provider_integrity_anomalies%rowtype;
  v_result boolean;
begin
  if p_event_id is null or char_length(p_event_id) not between 1 and 255
    or p_event_id !~ '^[[:graph:]]+$'
    or p_event_type is null or p_event_type not in ('suppression.added', 'suppression.removed')
    or p_provider_suppression_id is null
    or char_length(p_provider_suppression_id) not between 1 and 255
    or p_provider_suppression_id !~ '^[[:graph:]]+$'
    or p_recipient_email is null
    or char_length(p_recipient_email) > 320
    or p_suppression_origin is null
    or p_suppression_origin not in ('bounce', 'complaint', 'manual')
    or (p_suppression_source_id is not null
      and (char_length(p_suppression_source_id) not between 1 and 255
        or p_suppression_source_id !~ '^[[:graph:]]+$'))
    or p_suppression_created_at is null
    or p_provider_created_at is null
    or p_payload_fingerprint is null
    or p_payload_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid provider suppression event.' using errcode = '22023';
  end if;

  v_email := lower(btrim(p_recipient_email));
  if char_length(v_email) not between 3 and 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Invalid provider suppression recipient.' using errcode = '22023';
  end if;

  -- Global order: event identity, normalized recipient, then suppression correlation.
  perform pg_catalog.pg_advisory_xact_lock(20261118, pg_catalog.hashtext(p_event_id));
  perform pg_catalog.pg_advisory_xact_lock(20261119, pg_catalog.hashtext(v_email));
  perform pg_catalog.pg_advisory_xact_lock(20261127, pg_catalog.hashtext(p_provider_suppression_id));

  select e.* into v_existing
  from public.delivery_provider_events e
  where e.event_id = p_event_id
  for update;

  select e.* into v_related
  from public.delivery_provider_events e
  where e.provider_suppression_id = p_provider_suppression_id
    and e.recipient_email <> v_email
  order by e.received_at, e.event_id
  limit 1
  for update;

  if found then
    perform public._record_delivery_provider_integrity_conflict(
      v_email, p_event_id, v_related.event_id, 'provider_suppression_recipient_conflict',
      p_event_type, null, p_provider_suppression_id, p_provider_created_at,
      null, null, null, p_suppression_origin, p_suppression_source_id,
      p_suppression_created_at, p_payload_fingerprint,
      v_related.event_id, v_related.recipient_email
    );
    return null;
  end if;

  v_result := public._record_delivery_provider_suppression_event_pre037_impl(
    p_event_id,
    p_event_type,
    p_provider_suppression_id,
    v_email,
    p_suppression_origin,
    p_suppression_source_id,
    p_suppression_created_at,
    p_provider_created_at,
    p_payload_fingerprint
  );

  if v_result is null or v_result is true then
    select a.* into v_anomaly
    from public.delivery_provider_integrity_anomalies a
    where a.event_id = p_event_id
      and a.anomaly_type in ('duplicate_event_id_conflict', 'suppression_event_timestamp_conflict')
    order by a.detected_at desc
    limit 1;

    if found then
      select e.* into v_existing
      from public.delivery_provider_events e
      where e.event_id = coalesce(v_anomaly.related_event_id, v_anomaly.event_id)
      for update;

      if not found then
        raise exception 'Conflicting suppression event has no canonical event row.' using errcode = 'XX000';
      end if;

      perform public._record_delivery_provider_integrity_conflict(
        v_email,
        p_event_id,
        v_anomaly.related_event_id,
        v_anomaly.anomaly_type,
        p_event_type,
        null,
        p_provider_suppression_id,
        p_provider_created_at,
        null,
        null,
        null,
        p_suppression_origin,
        p_suppression_source_id,
        p_suppression_created_at,
        p_payload_fingerprint,
        v_existing.event_id,
        v_existing.recipient_email
      );
    elsif v_result is null then
      raise exception 'Provider suppression conflict was not durably classified.' using errcode = 'XX000';
    end if;
  end if;

  return v_result;
end;
$suppression_037$;

create function public.admin_list_delivery_provider_integrity_conflicts_page(
  p_state text default 'open',
  p_limit integer default 50,
  p_before_last_detected_at timestamptz default null,
  p_before_conflict_id bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $integrity_conflict_page$
declare
  v_total_count bigint;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator authorization is required.' using errcode = '42501';
  end if;
  if p_state is null or p_state not in ('open', 'resolved', 'all')
    or p_limit is null or p_limit not between 1 and 100
    or (p_before_last_detected_at is null) <> (p_before_conflict_id is null)
    or (p_before_conflict_id is not null and p_before_conflict_id <= 0) then
    raise exception 'Invalid provider-integrity case page parameters.' using errcode = '22023';
  end if;

  select count(*) into v_total_count
  from public.delivery_provider_integrity_cases c
  where p_state = 'all' or c.state = p_state;

  with page_plus_one as (
    select
      c.conflict_id,
      c.recipient_email,
      c.anomaly_type,
      c.state,
      c.first_detected_at,
      c.last_detected_at,
      (select count(*) from public.delivery_provider_integrity_conflict_evidence e
       where e.conflict_id = c.conflict_id)::bigint as evidence_count,
      c.resolved_at,
      c.resolved_by,
      c.resolution_note
    from public.delivery_provider_integrity_cases c
    where (p_state = 'all' or c.state = p_state)
      and (p_before_last_detected_at is null
        or (c.last_detected_at, c.conflict_id) < (p_before_last_detected_at, p_before_conflict_id))
    order by c.last_detected_at desc, c.conflict_id desc
    limit p_limit + 1
  ),
  page as (
    select * from page_plus_one
    order by last_detected_at desc, conflict_id desc
    limit p_limit
  ),
  metadata as (
    select count(*) > p_limit as has_more from page_plus_one
  ),
  tail as (
    select last_detected_at, conflict_id
    from page
    order by last_detected_at asc, conflict_id asc
    limit 1
  )
  select jsonb_build_object(
    'total_count', v_total_count,
    'has_more', metadata.has_more,
    'next_cursor', case when metadata.has_more then
      (select jsonb_build_object(
        'last_detected_at', tail.last_detected_at,
        'conflict_id', tail.conflict_id::text
      ) from tail)
      else null end,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'conflict_id', page.conflict_id::text,
        'recipient_email', page.recipient_email,
        'anomaly_type', page.anomaly_type,
        'state', page.state,
        'first_detected_at', page.first_detected_at,
        'last_detected_at', page.last_detected_at,
        'evidence_count', page.evidence_count,
        'resolved_at', page.resolved_at,
        'resolved_by', page.resolved_by,
        'resolution_note', page.resolution_note
      ) order by page.last_detected_at desc, page.conflict_id desc)
      from page
    ), '[]'::jsonb)
  ) into v_result
  from metadata;

  return v_result;
end;
$integrity_conflict_page$;

create function public.admin_get_delivery_provider_integrity_conflict(
  p_conflict_id bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $integrity_conflict_get$
declare
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator authorization is required.' using errcode = '42501';
  end if;
  if p_conflict_id is null or p_conflict_id <= 0 then
    raise exception 'A valid provider-integrity case ID is required.' using errcode = '22023';
  end if;

  select jsonb_build_object(
    'conflict_id', c.conflict_id::text,
    'recipient_email', c.recipient_email,
    'anomaly_type', c.anomaly_type,
    'state', c.state,
    'first_detected_at', c.first_detected_at,
    'last_detected_at', c.last_detected_at,
    'evidence_count', (
      select count(*) from public.delivery_provider_integrity_conflict_evidence e
      where e.conflict_id = c.conflict_id
    ),
    'history_count', (
      select count(*) from public.delivery_provider_integrity_conflict_history h
      where h.conflict_id = c.conflict_id
    ),
    'resolved_at', c.resolved_at,
    'resolved_by', c.resolved_by,
    'resolution_note', c.resolution_note,
    'latest_reopened', (
      select jsonb_build_object(
        'created_at', h.created_at,
        'note', h.note,
        'evidence_id', h.evidence_id::text
      )
      from public.delivery_provider_integrity_conflict_history h
      where h.conflict_id = c.conflict_id
        and h.action = 'reopened'
      order by h.created_at desc, h.history_id desc
      limit 1
    )
  ) into v_result
  from public.delivery_provider_integrity_cases c
  where c.conflict_id = p_conflict_id;

  return v_result;
end;
$integrity_conflict_get$;

create function public.admin_list_delivery_provider_integrity_evidence_page(
  p_conflict_id bigint,
  p_limit integer default 50,
  p_before_observed_at timestamptz default null,
  p_before_evidence_id bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $integrity_evidence_page$
declare
  v_total_count bigint;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator authorization is required.' using errcode = '42501';
  end if;
  if p_conflict_id is null or p_conflict_id <= 0
    or p_limit is null or p_limit not between 1 and 100
    or (p_before_observed_at is null) <> (p_before_evidence_id is null)
    or (p_before_evidence_id is not null and p_before_evidence_id <= 0) then
    raise exception 'Invalid provider-integrity evidence page parameters.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.delivery_provider_integrity_cases c where c.conflict_id = p_conflict_id) then
    raise exception 'Provider-integrity conflict case was not found.' using errcode = '22023';
  end if;

  select count(*) into v_total_count
  from public.delivery_provider_integrity_conflict_evidence e
  where e.conflict_id = p_conflict_id;

  with page_plus_one as (
    select e.*
    from public.delivery_provider_integrity_conflict_evidence e
    where e.conflict_id = p_conflict_id
      and (p_before_observed_at is null
        or (e.observed_at, e.evidence_id) < (p_before_observed_at, p_before_evidence_id))
    order by e.observed_at desc, e.evidence_id desc
    limit p_limit + 1
  ),
  page as (
    select * from page_plus_one
    order by observed_at desc, evidence_id desc
    limit p_limit
  ),
  metadata as (
    select count(*) > p_limit as has_more from page_plus_one
  ),
  tail as (
    select observed_at, evidence_id
    from page
    order by observed_at asc, evidence_id asc
    limit 1
  )
  select jsonb_build_object(
    'total_count', v_total_count,
    'has_more', metadata.has_more,
    'next_cursor', case when metadata.has_more then
      (select jsonb_build_object(
        'observed_at', tail.observed_at,
        'evidence_id', tail.evidence_id::text
      ) from tail)
      else null end,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'evidence_id', page.evidence_id::text,
        'observed_at', page.observed_at,
        'recipient_email', page.recipient_email,
        'event_id', page.event_id,
        'related_event_id', page.related_event_id,
        'event_type', page.event_type,
        'provider_email_id', page.provider_email_id,
        'provider_suppression_id', page.provider_suppression_id,
        'provider_created_at', page.provider_created_at,
        'bounce_type', page.bounce_type,
        'failure_class', page.failure_class,
        'suppression_reason', page.suppression_reason,
        'suppression_origin', page.suppression_origin,
        'suppression_source_id', page.suppression_source_id,
        'suppression_created_at', page.suppression_created_at,
        'payload_fingerprint', page.payload_fingerprint,
        'stored_event_id', page.stored_event_id,
        'stored_recipient_email', page.stored_recipient_email,
        'evidence_source', page.evidence_source
      ) order by page.observed_at desc, page.evidence_id desc)
      from page
    ), '[]'::jsonb)
  ) into v_result
  from metadata;

  return v_result;
end;
$integrity_evidence_page$;

create function public.admin_list_delivery_provider_integrity_history_page(
  p_conflict_id bigint,
  p_limit integer default 50,
  p_before_created_at timestamptz default null,
  p_before_history_id bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $integrity_history_page$
declare
  v_total_count bigint;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator authorization is required.' using errcode = '42501';
  end if;
  if p_conflict_id is null or p_conflict_id <= 0
    or p_limit is null or p_limit not between 1 and 100
    or (p_before_created_at is null) <> (p_before_history_id is null)
    or (p_before_history_id is not null and p_before_history_id <= 0) then
    raise exception 'Invalid provider-integrity history page parameters.' using errcode = '22023';
  end if;
  if not exists (select 1 from public.delivery_provider_integrity_cases c where c.conflict_id = p_conflict_id) then
    raise exception 'Provider-integrity conflict case was not found.' using errcode = '22023';
  end if;

  select count(*) into v_total_count
  from public.delivery_provider_integrity_conflict_history h
  where h.conflict_id = p_conflict_id;

  with page_plus_one as (
    select h.*
    from public.delivery_provider_integrity_conflict_history h
    where h.conflict_id = p_conflict_id
      and (p_before_created_at is null
        or (h.created_at, h.history_id) < (p_before_created_at, p_before_history_id))
    order by h.created_at desc, h.history_id desc
    limit p_limit + 1
  ),
  page as (
    select * from page_plus_one
    order by created_at desc, history_id desc
    limit p_limit
  ),
  metadata as (
    select count(*) > p_limit as has_more from page_plus_one
  ),
  tail as (
    select created_at, history_id
    from page
    order by created_at asc, history_id asc
    limit 1
  )
  select jsonb_build_object(
    'total_count', v_total_count,
    'has_more', metadata.has_more,
    'next_cursor', case when metadata.has_more then
      (select jsonb_build_object(
        'created_at', tail.created_at,
        'history_id', tail.history_id::text
      ) from tail)
      else null end,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'history_id', page.history_id::text,
        'action', page.action,
        'actor_id', page.actor_id,
        'note', page.note,
        'evidence_id', page.evidence_id::text,
        'created_at', page.created_at
      ) order by page.created_at desc, page.history_id desc)
      from page
    ), '[]'::jsonb)
  ) into v_result
  from metadata;

  return v_result;
end;
$integrity_history_page$;

revoke all privileges on function public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text) to service_role;
comment on function public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text,text)
  is 'deedlight:038:event-id-recipient-provider-lock-order:v1';

revoke all privileges on function public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text) to service_role;
comment on function public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text,text)
  is 'deedlight:038:event-id-recipient-provider-lock-order:v1';

revoke all privileges on function public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text) to service_role;
comment on function public.record_delivery_provider_lifecycle_event(text,text,text,text,timestamptz,text,text)
  is 'deedlight:038:event-id-recipient-provider-lock-order:v1';

revoke all privileges on function public.record_delivery_provider_event(text,text,text,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.record_delivery_provider_event(text,text,text,text,text) to service_role;
comment on function public.record_delivery_provider_event(text,text,text,text,text)
  is 'deedlight:038:event-id-recipient-provider-lock-order:v1';

revoke all privileges on function public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)
  from public, anon, authenticated, service_role;
grant execute on function public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)
  to service_role;
comment on function public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)
  is 'deedlight:038:event-id-recipient-provider-lock-order:v1';

revoke all privileges on function public.admin_list_delivery_provider_integrity_conflicts_page(text,integer,timestamptz,bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.admin_list_delivery_provider_integrity_conflicts_page(text,integer,timestamptz,bigint)
  to authenticated;

revoke all privileges on function public.admin_get_delivery_provider_integrity_conflict(bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.admin_get_delivery_provider_integrity_conflict(bigint)
  to authenticated;

revoke all privileges on function public.admin_list_delivery_provider_integrity_evidence_page(bigint,integer,timestamptz,bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.admin_list_delivery_provider_integrity_evidence_page(bigint,integer,timestamptz,bigint)
  to authenticated;

revoke all privileges on function public.admin_list_delivery_provider_integrity_history_page(bigint,integer,timestamptz,bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.admin_list_delivery_provider_integrity_history_page(bigint,integer,timestamptz,bigint)
  to authenticated;

comment on function public.admin_list_delivery_provider_integrity_conflicts_page(text,integer,timestamptz,bigint)
  is 'Admin-only keyset page of private provider-integrity cases with exact filtered total and continuation cursor.';
comment on function public.admin_get_delivery_provider_integrity_conflict(bigint)
  is 'Admin-only direct case retrieval independent of list pagination; includes exact counts and latest reopening summary.';
comment on function public.admin_list_delivery_provider_integrity_evidence_page(bigint,integer,timestamptz,bigint)
  is 'Admin-only keyset page of append-only normalized provider evidence with exact total and continuation cursor.';
comment on function public.admin_list_delivery_provider_integrity_history_page(bigint,integer,timestamptz,bigint)
  is 'Admin-only newest-first keyset page of append-only resolution/reopening history with exact total and continuation cursor.';

notify pgrst, 'reload schema';
commit;
