\set ON_ERROR_STOP on

-- Migrations 032 and 033 are applied by the caller after migrations 025-029.
do $suppression_acl$
begin
  if has_function_privilege('anon',
       'public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)','EXECUTE')
    or has_function_privilege('authenticated',
       'public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)','EXECUTE')
    or not has_function_privilege('service_role',
       'public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)','EXECUTE')
    or has_table_privilege('anon','public.delivery_provider_suppression_state','SELECT')
    or has_table_privilege('authenticated','public.delivery_provider_suppression_state','SELECT')
    or has_table_privilege('service_role','public.delivery_provider_suppression_state','SELECT')
    or not (select relrowsecurity from pg_class where oid='public.delivery_provider_suppression_state'::regclass)
    or exists (
      select 1
      from pg_proc p
      cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      where p.oid = to_regprocedure(
        'public.record_delivery_provider_suppression_event(text,text,text,text,text,text,timestamptz,timestamptz,text)'
      )
        and a.grantee = 0 and a.privilege_type = 'EXECUTE'
    ) then
    raise exception 'Provider suppression synchronization ACL boundary regressed.';
  end if;
end;
$suppression_acl$;

set role service_role;
do $manual_add_remove$
begin
  if public.record_delivery_provider_suppression_event(
    'evt_sup_manual_add_1','suppression.added','sup_manual_1','manual-sync@example.test',
    'manual',null,'2026-11-22T09:59:00Z','2026-11-22T10:00:00Z',repeat('a',64)
  ) is not true then
    raise exception 'Manual suppression.added was not recorded.';
  end if;

  if public.record_delivery_provider_suppression_event(
    'evt_sup_manual_add_1','suppression.added','sup_manual_1','manual-sync@example.test',
    'manual',null,'2026-11-22T09:59:00Z','2026-11-22T10:00:00Z',repeat('a',64)
  ) is not false then
    raise exception 'Exact duplicate suppression event was not a successful no-op.';
  end if;

  if public.record_delivery_provider_suppression_event(
    'evt_sup_manual_add_1','suppression.removed','sup_manual_1','manual-sync@example.test',
    'manual',null,'2026-11-22T09:59:00Z','2026-11-22T10:05:00Z',repeat('b',64)
  ) is not null then
    raise exception 'Conflicting suppression event ID was not rejected as an integrity anomaly.';
  end if;

  if public.record_delivery_provider_suppression_event(
    'evt_sup_manual_remove_1','suppression.removed','sup_manual_1','manual-sync@example.test',
    'manual',null,'2026-11-22T09:59:00Z','2026-11-22T10:05:00Z',repeat('b',64)
  ) is not true then
    raise exception 'Manual suppression.removed was not recorded.';
  end if;
end;
$manual_add_remove$;
reset role;

do $manual_assert$
begin
  if exists (
    select 1 from public.delivery_provider_suppressions
    where recipient_email='manual-sync@example.test'
  ) then
    raise exception 'Manual provider suppression was not cleared after its matching removal.';
  end if;
  if not exists (
    select 1 from public.delivery_provider_suppression_state
    where recipient_email='manual-sync@example.test'
      and provider_suppression_id='sup_manual_1'
      and origin='manual' and is_active=false
      and event_id='evt_sup_manual_remove_1'
  ) then
    raise exception 'Manual suppression state did not project the latest provider event.';
  end if;
  if not exists (
    select 1 from public.delivery_provider_integrity_anomalies
    where event_id='evt_sup_manual_add_1'
      and anomaly_type='duplicate_event_id_conflict'
  ) then
    raise exception 'Conflicting duplicate suppression event was not recorded.';
  end if;
end;
$manual_assert$;

set role service_role;
do $complaint_origin$
begin
  perform public.record_delivery_provider_suppression_event(
    'evt_sup_complaint_add','suppression.added','sup_complaint_1','suppression-complaint@example.test',
    'complaint','resend_email_complaint_1','2026-11-22T10:59:00Z','2026-11-22T11:00:00Z',repeat('c',64)
  );
  perform public.record_delivery_provider_suppression_event(
    'evt_sup_complaint_remove','suppression.removed','sup_complaint_1','suppression-complaint@example.test',
    'complaint','resend_email_complaint_1','2026-11-22T10:59:00Z','2026-11-22T11:05:00Z',repeat('d',64)
  );
end;
$complaint_origin$;

do $bounce_origin$
begin
  perform public.record_delivery_provider_suppression_event(
    'evt_sup_bounce_add','suppression.added','sup_bounce_1','suppression-bounce@example.test',
    'bounce','resend_email_bounce_1','2026-11-22T11:09:00Z','2026-11-22T11:10:00Z',repeat('e',64)
  );
  perform public.record_delivery_provider_suppression_event(
    'evt_sup_bounce_remove','suppression.removed','sup_bounce_1','suppression-bounce@example.test',
    'bounce','resend_email_bounce_1','2026-11-22T11:09:00Z','2026-11-22T11:15:00Z',repeat('f',64)
  );
end;
$bounce_origin$;
reset role;

do $origin_assert$
begin
  if (select reason from public.delivery_provider_suppressions
      where recipient_email='suppression-complaint@example.test') is distinct from 'complaint' then
    raise exception 'suppression.removed cleared a complaint-origin hold.';
  end if;
  if (select reason from public.delivery_provider_suppressions
      where recipient_email='suppression-bounce@example.test') is distinct from 'permanent_bounce' then
    raise exception 'suppression.removed cleared a bounce-origin hold.';
  end if;
  if (select is_active from public.delivery_provider_suppression_state
      where recipient_email='suppression-complaint@example.test') is not false
    or (select is_active from public.delivery_provider_suppression_state
      where recipient_email='suppression-bounce@example.test') is not false then
    raise exception 'Removed provider suppression state did not become inactive.';
  end if;
end;
$origin_assert$;

-- An independently recorded complaint must survive removal of a manual provider entry.
set role service_role;
do $independent_complaint$
begin
  perform public.record_delivery_provider_lifecycle_event(
    'evt_sup_independent_complaint','email.complained','resend_sup_independent_complaint',
    'independent-complaint@example.test','2026-11-22T12:00:00Z',null,null,null,repeat('1',64)
  );
  perform public.record_delivery_provider_suppression_event(
    'evt_sup_independent_manual_add','suppression.added','sup_independent_manual',
    'independent-complaint@example.test','manual',null,
    '2026-11-22T12:01:00Z','2026-11-22T12:02:00Z',repeat('2',64)
  );
  perform public.record_delivery_provider_suppression_event(
    'evt_sup_independent_manual_remove','suppression.removed','sup_independent_manual',
    'independent-complaint@example.test','manual',null,
    '2026-11-22T12:01:00Z','2026-11-22T12:03:00Z',repeat('3',64)
  );
end;
$independent_complaint$;

-- An independently recorded permanent bounce must survive manual provider removal.
do $independent_bounce$
begin
  perform public.record_delivery_provider_lifecycle_event(
    'evt_sup_independent_bounce','email.bounced','resend_sup_independent_bounce',
    'independent-bounce@example.test','2026-11-22T12:10:00Z','Permanent',null,null,repeat('4',64)
  );
  perform public.record_delivery_provider_suppression_event(
    'evt_sup_independent_bounce_add','suppression.added','sup_independent_bounce',
    'independent-bounce@example.test','manual',null,
    '2026-11-22T12:11:00Z','2026-11-22T12:12:00Z',repeat('5',64)
  );
  perform public.record_delivery_provider_suppression_event(
    'evt_sup_independent_bounce_remove','suppression.removed','sup_independent_bounce',
    'independent-bounce@example.test','manual',null,
    '2026-11-22T12:11:00Z','2026-11-22T12:13:00Z',repeat('6',64)
  );
end;
$independent_bounce$;
reset role;

do $independent_assert$
begin
  if (select reason from public.delivery_provider_suppressions
      where recipient_email='independent-complaint@example.test') is distinct from 'complaint' then
    raise exception 'Manual suppression removal cleared an independent complaint.';
  end if;
  if (select reason from public.delivery_provider_suppressions
      where recipient_email='independent-bounce@example.test') is distinct from 'permanent_bounce' then
    raise exception 'Manual suppression removal cleared an independent permanent bounce.';
  end if;
end;
$independent_assert$;

-- Provider event timestamps, not receipt order, control the suppression projection.
set role service_role;
do $out_of_order_remove_first$
begin
  perform public.record_delivery_provider_lifecycle_event(
    'evt_sup_out_of_order_email_suppressed','email.suppressed','resend_sup_out_of_order',
    'suppression-out-of-order@example.test','2026-11-22T13:00:00Z',null,null,'provider_suppressed',repeat('7',64)
  );
  perform public.record_delivery_provider_suppression_event(
    'evt_sup_out_of_order_remove','suppression.removed','sup_out_of_order',
    'suppression-out-of-order@example.test','manual',null,
    '2026-11-22T12:00:00Z','2026-11-22T13:05:00Z',repeat('8',64)
  );
end;
$out_of_order_remove_first$;
reset role;

do $out_of_order_remove_assert$
begin
  if not exists (
    select 1 from public.delivery_provider_suppressions
    where recipient_email='suppression-out-of-order@example.test'
      and reason='provider_suppressed'
  ) then
    raise exception 'A removal without its matching add cleared an existing provider suppression.';
  end if;
end;
$out_of_order_remove_assert$;

set role service_role;
do $out_of_order_add_after_remove$
begin
  perform public.record_delivery_provider_suppression_event(
    'evt_sup_out_of_order_add','suppression.added','sup_out_of_order',
    'suppression-out-of-order@example.test','manual',null,
    '2026-11-22T12:00:00Z','2026-11-22T13:01:00Z',repeat('9',64)
  );
end;
$out_of_order_add_after_remove$;

do $out_of_order_add_first$
begin
  perform public.record_delivery_provider_suppression_event(
    'evt_sup_out_of_order_newer_add','suppression.added','sup_out_of_order_newer',
    'suppression-out-of-order-active@example.test','manual',null,
    '2026-11-22T14:00:00Z','2026-11-22T14:10:00Z',repeat('a',64)
  );
  perform public.record_delivery_provider_suppression_event(
    'evt_sup_out_of_order_older_remove','suppression.removed','sup_out_of_order_newer',
    'suppression-out-of-order-active@example.test','manual',null,
    '2026-11-22T14:00:00Z','2026-11-22T14:05:00Z',repeat('b',64)
  );
end;
$out_of_order_add_first$;

-- Equal provider timestamps with contradictory add/remove state fail closed.
do $equal_time_conflict$
begin
  perform public.record_delivery_provider_suppression_event(
    'evt_sup_equal_time_add','suppression.added','sup_equal_time',
    'suppression-equal-time@example.test','manual',null,
    '2026-11-22T15:00:00Z','2026-11-22T15:01:00Z',repeat('c',64)
  );
  perform public.record_delivery_provider_suppression_event(
    'evt_sup_equal_time_remove','suppression.removed','sup_equal_time',
    'suppression-equal-time@example.test','manual',null,
    '2026-11-22T15:00:00Z','2026-11-22T15:01:00Z',repeat('d',64)
  );
end;
$equal_time_conflict$;
reset role;

do $out_of_order_assert$
begin
  if exists (
    select 1 from public.delivery_provider_suppressions
    where recipient_email='suppression-out-of-order@example.test'
  ) or (select is_active from public.delivery_provider_suppression_state
        where recipient_email='suppression-out-of-order@example.test') is not false then
    raise exception 'Older suppression.added regressed a later removal.';
  end if;

  if (select is_active from public.delivery_provider_suppression_state
      where recipient_email='suppression-out-of-order-active@example.test') is not true
    or not exists (
      select 1 from public.delivery_provider_suppressions
      where recipient_email='suppression-out-of-order-active@example.test'
        and reason='provider_suppressed'
    ) then
    raise exception 'Older suppression.removed regressed a later addition.';
  end if;

  if (select is_active from public.delivery_provider_suppression_state
      where recipient_email='suppression-equal-time@example.test') is not true
    or not exists (
      select 1 from public.delivery_provider_integrity_anomalies
      where event_id='evt_sup_equal_time_remove'
        and related_event_id='evt_sup_equal_time_add'
        and anomaly_type='suppression_event_timestamp_conflict'
    ) then
    raise exception 'Equal-time contradictory suppression events did not fail closed.';
  end if;
end;
$out_of_order_assert$;

-- A suppression ID is permanently bound to one normalized recipient.
set role service_role;
do $cross_recipient$
declare v_rejected boolean := false;
begin
  perform public.record_delivery_provider_suppression_event(
    'evt_sup_cross_recipient_first','suppression.added','sup_cross_recipient',
    'suppression-first@example.test','manual',null,
    '2026-11-22T16:00:00Z','2026-11-22T16:01:00Z',repeat('e',64)
  );

  begin
    perform public.record_delivery_provider_suppression_event(
      'evt_sup_cross_recipient_second','suppression.removed','sup_cross_recipient',
      'suppression-second@example.test','manual',null,
      '2026-11-22T16:00:00Z','2026-11-22T16:02:00Z',repeat('f',64)
    );
  exception when sqlstate '22023' then
    v_rejected := true;
  end;

  if not v_rejected then
    raise exception 'Cross-recipient suppression ID reuse was accepted.';
  end if;
end;
$cross_recipient$;
reset role;

do $cross_recipient_assert$
begin
  if (select count(*) from public.delivery_provider_events
      where provider_suppression_id='sup_cross_recipient') <> 1
    or exists (
      select 1 from public.delivery_provider_events
      where event_id='evt_sup_cross_recipient_second'
    )
    or exists (
      select 1 from public.delivery_provider_suppression_state
      where recipient_email='suppression-second@example.test'
    )
    or (select is_active from public.delivery_provider_suppression_state
        where recipient_email='suppression-first@example.test') is not true then
    raise exception 'Cross-recipient suppression ID conflict mutated event history or state.';
  end if;
end;
$cross_recipient_assert$;

-- Historical generic suppression with no trustworthy provider timestamp is ambiguous and must remain blocked.
insert into public.delivery_provider_events (
  event_id,event_type,provider_email_id,recipient_email,provider_created_at,
  bounce_type,failure_class,suppression_reason,payload_fingerprint
) values (
  'evt_c331_unknown_timestamp_lifecycle','email.suppressed','resend_c331_unknown_timestamp',
  'cross-stream-unknown-time@example.test',null,null,null,null,null
);
insert into public.delivery_provider_suppressions (recipient_email,reason,provider_event_id)
values ('cross-stream-unknown-time@example.test','provider_suppressed','evt_c331_unknown_timestamp_lifecycle');
-- Cross-stream lifecycle events must respect the newer manual suppression-list projection.
set role service_role;
do $cross_stream_manual_remove$
begin
  perform public.record_delivery_provider_suppression_event(
    'evt_c323_cross_stream_manual_add','suppression.added','sup_c323_cross_stream_manual',
    'cross-stream-manual@example.test','manual',null,
    '2026-11-22T17:00:00Z','2026-11-22T17:01:00Z',repeat('1',64)
  );
  perform public.record_delivery_provider_suppression_event(
    'evt_c323_cross_stream_manual_remove','suppression.removed','sup_c323_cross_stream_manual',
    'cross-stream-manual@example.test','manual',null,
    '2026-11-22T17:00:00Z','2026-11-22T17:02:00Z',repeat('2',64)
  );
  perform public.record_delivery_provider_lifecycle_event(
    'evt_c323_cross_stream_old_email_suppressed','email.suppressed','resend_c323_cross_stream_manual',
    'cross-stream-manual@example.test','2026-11-22T17:00:00Z',null,null,'provider_suppressed',repeat('3',64)
  );

  -- A removal without its matching add is not authority to clear a generic block.
  perform public.record_delivery_provider_lifecycle_event(
    'evt_c323_cross_stream_no_add_initial','email.suppressed','resend_c323_cross_stream_no_add_initial',
    'cross-stream-no-add@example.test','2026-11-22T17:18:00Z',null,null,'provider_suppressed',repeat('d',64)
  );
  perform public.record_delivery_provider_suppression_event(
    'evt_c323_cross_stream_no_add_remove','suppression.removed','sup_c323_cross_stream_no_add',
    'cross-stream-no-add@example.test','manual',null,
    '2026-11-22T17:18:00Z','2026-11-22T17:19:00Z',repeat('e',64)
  );
  perform public.record_delivery_provider_lifecycle_event(
    'evt_c323_cross_stream_no_add_old_lifecycle','email.suppressed','resend_c323_cross_stream_no_add_old',
    'cross-stream-no-add@example.test','2026-11-22T17:18:30Z',null,null,'provider_suppressed',repeat('f',64)
  );

  -- Equal timestamps are ambiguous and remain blocked.
  perform public.record_delivery_provider_suppression_event(
    'evt_c323_cross_stream_equal_add','suppression.added','sup_c323_cross_stream_equal',
    'cross-stream-equal@example.test','manual',null,
    '2026-11-22T17:09:00Z','2026-11-22T17:10:00Z',repeat('4',64)
  );
  perform public.record_delivery_provider_suppression_event(
    'evt_c323_cross_stream_equal_remove','suppression.removed','sup_c323_cross_stream_equal',
    'cross-stream-equal@example.test','manual',null,
    '2026-11-22T17:09:00Z','2026-11-22T17:11:00Z',repeat('5',64)
  );
  perform public.record_delivery_provider_lifecycle_event(
    'evt_c323_cross_stream_equal_email_suppressed','email.suppressed','resend_c323_cross_stream_equal',
    'cross-stream-equal@example.test','2026-11-22T17:11:00Z',null,null,'provider_suppressed',repeat('6',64)
  );

  perform public.record_delivery_provider_suppression_event(
    'evt_c331_unknown_timestamp_add','suppression.added','sup_c331_unknown_timestamp',
    'cross-stream-unknown-time@example.test','manual',null,
    '2026-11-22T23:00:00Z','2026-11-22T23:01:00Z',repeat('7',64)
  );
  perform public.record_delivery_provider_suppression_event(
    'evt_c331_unknown_timestamp_remove','suppression.removed','sup_c331_unknown_timestamp',
    'cross-stream-unknown-time@example.test','manual',null,
    '2026-11-22T23:00:00Z','2026-11-22T23:02:00Z',repeat('8',64)
  );
  -- Older manual removal processed before newer lifecycle evidence must not clear it.
  perform public.record_delivery_provider_suppression_event('evt_c331_removal_first_add','suppression.added','sup_c331_removal_first','cross-stream-removal-first-older@example.test','manual',null,'2026-11-22T19:00:00Z','2026-11-22T19:01:00Z',repeat('a',64));
  perform public.record_delivery_provider_suppression_event('evt_c331_removal_first_remove','suppression.removed','sup_c331_removal_first','cross-stream-removal-first-older@example.test','manual',null,'2026-11-22T19:00:00Z','2026-11-22T19:02:00Z',repeat('b',64));
  perform public.record_delivery_provider_lifecycle_event('evt_c331_removal_first_lifecycle','email.suppressed','resend_c331_removal_first','cross-stream-removal-first-older@example.test','2026-11-22T19:03:00Z',null,null,'provider_suppressed',repeat('c',64));

  -- Newer lifecycle evidence first, then an older manual removal.
  perform public.record_delivery_provider_suppression_event('evt_c331_lifecycle_first_add','suppression.added','sup_c331_lifecycle_first','cross-stream-lifecycle-first-older@example.test','manual',null,'2026-11-22T20:00:00Z','2026-11-22T20:01:00Z',repeat('d',64));
  perform public.record_delivery_provider_lifecycle_event('evt_c331_lifecycle_first_suppressed','email.suppressed','resend_c331_lifecycle_first','cross-stream-lifecycle-first-older@example.test','2026-11-22T20:03:00Z',null,null,'provider_suppressed',repeat('e',64));
  perform public.record_delivery_provider_suppression_event('evt_c331_lifecycle_first_old_remove','suppression.removed','sup_c331_lifecycle_first','cross-stream-lifecycle-first-older@example.test','manual',null,'2026-11-22T20:00:00Z','2026-11-22T20:02:00Z',repeat('f',64));

  -- Equal-time evidence is ambiguous and remains blocked when removal arrives second.
  perform public.record_delivery_provider_suppression_event('evt_c331_equal_lifecycle_first_add','suppression.added','sup_c331_equal_lifecycle_first','cross-stream-equal-lifecycle-first@example.test','manual',null,'2026-11-22T21:00:00Z','2026-11-22T21:01:00Z',repeat('1',64));
  perform public.record_delivery_provider_lifecycle_event('evt_c331_equal_lifecycle_first_suppressed','email.suppressed','resend_c331_equal_lifecycle_first','cross-stream-equal-lifecycle-first@example.test','2026-11-22T21:02:00Z',null,null,'provider_suppressed',repeat('2',64));
  perform public.record_delivery_provider_suppression_event('evt_c331_equal_lifecycle_first_remove','suppression.removed','sup_c331_equal_lifecycle_first','cross-stream-equal-lifecycle-first@example.test','manual',null,'2026-11-22T21:00:00Z','2026-11-22T21:02:00Z',repeat('3',64));

  -- A genuinely newer manual removal remains authoritative.
  perform public.record_delivery_provider_suppression_event('evt_c331_newer_lifecycle_first_add','suppression.added','sup_c331_newer_lifecycle_first','cross-stream-newer-lifecycle-first@example.test','manual',null,'2026-11-22T22:00:00Z','2026-11-22T22:01:00Z',repeat('4',64));
  perform public.record_delivery_provider_lifecycle_event('evt_c331_newer_lifecycle_first_suppressed','email.suppressed','resend_c331_newer_lifecycle_first','cross-stream-newer-lifecycle-first@example.test','2026-11-22T22:02:00Z',null,null,'provider_suppressed',repeat('5',64));
  perform public.record_delivery_provider_suppression_event('evt_c331_newer_lifecycle_first_remove','suppression.removed','sup_c331_newer_lifecycle_first','cross-stream-newer-lifecycle-first@example.test','manual',null,'2026-11-22T22:00:00Z','2026-11-22T22:03:00Z',repeat('6',64));
  -- Reasoned provider events still establish independent DeedLight holds.
  perform public.record_delivery_provider_suppression_event(
    'evt_c323_cross_stream_complaint_add','suppression.added','sup_c323_cross_stream_complaint',
    'cross-stream-complaint@example.test','manual',null,
    '2026-11-22T17:12:00Z','2026-11-22T17:13:00Z',repeat('7',64)
  );
  perform public.record_delivery_provider_suppression_event(
    'evt_c323_cross_stream_complaint_remove','suppression.removed','sup_c323_cross_stream_complaint',
    'cross-stream-complaint@example.test','manual',null,
    '2026-11-22T17:12:00Z','2026-11-22T17:14:00Z',repeat('8',64)
  );
  perform public.record_delivery_provider_lifecycle_event(
    'evt_c323_cross_stream_previous_complaint','email.suppressed','resend_c323_cross_stream_complaint',
    'cross-stream-complaint@example.test','2026-11-22T17:12:00Z',null,null,'previous_complaint',repeat('9',64)
  );

  perform public.record_delivery_provider_suppression_event(
    'evt_c323_cross_stream_bounce_add','suppression.added','sup_c323_cross_stream_bounce',
    'cross-stream-bounce@example.test','manual',null,
    '2026-11-22T17:15:00Z','2026-11-22T17:16:00Z',repeat('a',64)
  );
  perform public.record_delivery_provider_suppression_event(
    'evt_c323_cross_stream_bounce_remove','suppression.removed','sup_c323_cross_stream_bounce',
    'cross-stream-bounce@example.test','manual',null,
    '2026-11-22T17:15:00Z','2026-11-22T17:17:00Z',repeat('b',64)
  );
  perform public.record_delivery_provider_lifecycle_event(
    'evt_c323_cross_stream_previous_bounce','email.suppressed','resend_c323_cross_stream_bounce',
    'cross-stream-bounce@example.test','2026-11-22T17:15:00Z',null,null,'previous_bounce',repeat('c',64)
  );
end;
$cross_stream_manual_remove$;
reset role;

do $cross_stream_assert$
begin
  if exists (
    select 1 from public.delivery_provider_suppressions
    where recipient_email='cross-stream-manual@example.test'
  ) or (select is_active from public.delivery_provider_suppression_state
        where recipient_email='cross-stream-manual@example.test') is not false then
    raise exception 'Older email.suppressed lifecycle event reinstated a newer manual provider removal.';
  end if;

  if (select reason from public.delivery_provider_suppressions where recipient_email='cross-stream-removal-first-older@example.test') is distinct from 'provider_suppressed'
    or (select is_active from public.delivery_provider_suppression_state where recipient_email='cross-stream-removal-first-older@example.test') is not false then
    raise exception 'Older manual removal processed first erased newer lifecycle suppression evidence.';
  end if;
  if (select reason from public.delivery_provider_suppressions where recipient_email='cross-stream-lifecycle-first-older@example.test') is distinct from 'provider_suppressed'
    or (select is_active from public.delivery_provider_suppression_state where recipient_email='cross-stream-lifecycle-first-older@example.test') is not false then
    raise exception 'Older manual removal processed after newer lifecycle evidence cleared the provider hold.';
  end if;
  if (select reason from public.delivery_provider_suppressions where recipient_email='cross-stream-equal-lifecycle-first@example.test') is distinct from 'provider_suppressed'
    or (select is_active from public.delivery_provider_suppression_state where recipient_email='cross-stream-equal-lifecycle-first@example.test') is not false then
    raise exception 'Equal-time manual removal processed after lifecycle evidence did not fail closed.';
  end if;
  if exists (select 1 from public.delivery_provider_suppressions where recipient_email='cross-stream-newer-lifecycle-first@example.test')
    or (select is_active from public.delivery_provider_suppression_state where recipient_email='cross-stream-newer-lifecycle-first@example.test') is not false then
    raise exception 'A strictly newer manual removal did not clear the generic provider hold.';
  end if;
  if (select reason from public.delivery_provider_suppressions where recipient_email='cross-stream-unknown-time@example.test') is distinct from 'provider_suppressed'
    or (select is_active from public.delivery_provider_suppression_state where recipient_email='cross-stream-unknown-time@example.test') is not false then
    raise exception 'Unknown legacy lifecycle timestamp allowed a manual removal to clear provider suppression.';
  end if;
  if (select reason from public.delivery_provider_suppressions
      where recipient_email='cross-stream-no-add@example.test') is distinct from 'provider_suppressed' then
    raise exception 'Cross-stream lifecycle reconciliation cleared a removal without a matching manual add.';
  end if;

  if (select reason from public.delivery_provider_suppressions
      where recipient_email='cross-stream-equal@example.test') is distinct from 'provider_suppressed' then
    raise exception 'Equal-time cross-stream suppression did not fail closed.';
  end if;

  if (select reason from public.delivery_provider_suppressions
      where recipient_email='cross-stream-complaint@example.test') is distinct from 'complaint' then
    raise exception 'Cross-stream stale lifecycle handling cleared a previous_complaint hold.';
  end if;

  if (select reason from public.delivery_provider_suppressions
      where recipient_email='cross-stream-bounce@example.test') is distinct from 'permanent_bounce' then
    raise exception 'Cross-stream stale lifecycle handling cleared a previous_bounce hold.';
  end if;
end;
$cross_stream_assert$;



select jsonb_build_object(
  'suppression_add_remove_manual_sync','pass',
  'cross_stream_older_email_suppressed_after_manual_removal','pass',
  'cross_stream_older_removal_before_newer_lifecycle_keeps_hold','pass',
  'cross_stream_older_removal_after_newer_lifecycle_keeps_hold','pass',
  'cross_stream_equal_removal_after_lifecycle_keeps_hold','pass',
  'cross_stream_newer_removal_after_lifecycle_clears_hold','pass',
  'cross_stream_unknown_lifecycle_timestamp_fails_closed','pass',
  'cross_stream_equal_timestamp_fails_closed','pass',
  'cross_stream_removal_without_matching_add_keeps_hold','pass',
  'cross_stream_previous_complaint_and_bounce_holds','pass',
  'exact_duplicate_suppression_event','pass',
  'conflicting_duplicate_suppression_event','pass',
  'complaint_origin_survives_provider_removal','pass',
  'bounce_origin_survives_provider_removal','pass',
  'independent_complaint_survives_manual_removal','pass',
  'independent_bounce_survives_manual_removal','pass',
  'out_of_order_remove_before_add','pass',
  'out_of_order_add_before_remove','pass',
  'equal_timestamp_conflict_fails_closed','pass',
  'cross_recipient_suppression_id_binding','pass',
  'suppression_state_and_rpc_acl','pass'
) as delivery_provider_suppression_behavior;
