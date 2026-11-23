\set ON_ERROR_STOP on

BEGIN;

-- Synthetic identities only. The auth.users trigger creates matching profiles.
INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES
  ('00000000-0000-4000-8000-000000000101', 'private-member@privacy-test.invalid', '{"display_name":"Private Member"}'::jsonb),
  ('00000000-0000-4000-8000-000000000102', 'public-member@privacy-test.invalid', '{"display_name":"Public Member"}'::jsonb),
  ('00000000-0000-4000-8000-000000000103', 'suspended-member@privacy-test.invalid', '{"display_name":"Suspended Member"}'::jsonb),
  ('00000000-0000-4000-8000-000000000104', 'admin-member@privacy-test.invalid', '{"display_name":"Admin Member"}'::jsonb);

UPDATE public.profiles
SET username = 'private-member',
    display_name = 'Private Member',
    is_public = false,
    show_contribution_stats = false
WHERE user_id = '00000000-0000-4000-8000-000000000101';

UPDATE public.profiles
SET username = 'public-member',
    display_name = 'Public Member',
    is_public = true,
    show_contribution_stats = true
WHERE user_id = '00000000-0000-4000-8000-000000000102';

UPDATE public.profiles
SET username = 'suspended-member',
    display_name = 'Suspended Member',
    is_public = true,
    is_suspended = true
WHERE user_id = '00000000-0000-4000-8000-000000000103';

UPDATE public.profiles
SET username = 'admin-member',
    display_name = 'Admin Member',
    role = 'admin',
    is_public = false
WHERE user_id = '00000000-0000-4000-8000-000000000104';

INSERT INTO public.offerings (
  id, user_id, offering_type, title, body, is_anonymous, status,
  published_at, moderation_note
)
VALUES
  (
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000101',
    'good_deed', 'Anonymous good deed',
    'Synthetic anonymous Offering used only by the database regression suite.',
    true, 'approved', now(), null
  ),
  (
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000102',
    'good_deed', 'Public good deed',
    'Synthetic public Offering used only by the database regression suite.',
    false, 'approved', now(), null
  ),
  (
    '00000000-0000-4000-8000-000000000203',
    '00000000-0000-4000-8000-000000000101',
    'good_deed', 'Rejected good deed',
    'Synthetic rejected Offering used only by the database regression suite.',
    false, 'rejected', null, 'C296_REJECTED_MODERATION_SENTINEL C296_INTERNAL_MODERATION_NOTE_SENTINEL'
  ),
  (
    '00000000-0000-4000-8000-000000000204',
    '00000000-0000-4000-8000-000000000102',
    'good_deed', 'Moderator hidden deed',
    'Synthetic moderator-hidden Offering used only by the database regression suite.',
    false, 'hidden', null, 'C296_MODERATOR_HIDDEN_SENTINEL'
  ),
  (
    '00000000-0000-4000-8000-000000000205',
    '00000000-0000-4000-8000-000000000103',
    'good_deed', 'Suspended member deed',
    'Synthetic suspended-member Offering used only by the database regression suite.',
    false, 'approved', now(), null
  );

INSERT INTO public.saved_lights (id, user_id, offering_id)
VALUES
  (
    '00000000-0000-4000-8000-000000000301',
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000202'
  ),
  (
    '00000000-0000-4000-8000-000000000302',
    '00000000-0000-4000-8000-000000000102',
    '00000000-0000-4000-8000-000000000201'
  );

INSERT INTO public.reactions (id, offering_id, user_id, reaction_type)
VALUES (
  '00000000-0000-4000-8000-000000000303',
  '00000000-0000-4000-8000-000000000201',
  '00000000-0000-4000-8000-000000000102',
  'bless'
);

INSERT INTO public.reports (
  id, offering_id, reported_by, reason, details, status, admin_note
)
VALUES (
  '00000000-0000-4000-8000-000000000304',
  '00000000-0000-4000-8000-000000000201',
  '00000000-0000-4000-8000-000000000102',
  'privacy_concern',
  'C296_INTERNAL_REPORT_DETAILS_SENTINEL',
  'open',
  'C296_INTERNAL_REPORT_ADMIN_NOTE_SENTINEL'
);

INSERT INTO public.member_moderation_events (
  id, member_user_id, actor_user_id, action, reason
)
VALUES (
  '00000000-0000-4000-8000-000000000305',
  '00000000-0000-4000-8000-000000000101',
  '00000000-0000-4000-8000-000000000104',
  'restored',
  'C296_INTERNAL_MODERATION_EVENT_SENTINEL'
);

INSERT INTO public.reflections (id, offering_id, user_id, body, status)
VALUES (
  '00000000-0000-4000-8000-000000000306',
  '00000000-0000-4000-8000-000000000201',
  '00000000-0000-4000-8000-000000000101',
  'C296_PRIVATE_OFFERING_REFLECTION_SENTINEL',
  'hidden'
);

INSERT INTO public.daily_posts (
  date, slug, title, reflection, daily_action, status, published_at
)
VALUES (
  current_date,
  'c296-privacy-test-daily-post',
  'C296 privacy test Daily Light',
  'Synthetic Daily Light row used only by the privacy database test.',
  'No action; this fixture exists only inside the test transaction.',
  'published',
  now()
);

INSERT INTO public.daily_reflections (
  user_id, daily_post_id, reflection_text, is_private
)
SELECT
  '00000000-0000-4000-8000-000000000101',
  dp.id,
  'C296_PRIVATE_DAILY_REFLECTION_SENTINEL',
  true
FROM public.daily_posts dp
WHERE dp.slug = 'c296-privacy-test-daily-post';


-- Current Daily Light Journey and private member-data fixtures.
INSERT INTO public.daily_lights (
  id, scheduled_date, status, title, summary, small_deed, reflection_prompt
) VALUES (
  '00000000-0000-4000-8000-000000000401',
  current_date + 1, 'published', 'Privacy test Daily Light',
  'Synthetic private Journey fixture.', 'A quiet act of kindness.',
  'What mattered today?'
);

INSERT INTO public.daily_reflections (user_id, daily_light_id, reflection, intention)
VALUES
  ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000401', 'C296_PRIVATE_JOURNEY_REFLECTION_A', 'C296_PRIVATE_JOURNEY_INTENTION_A'),
  ('00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-000000000401', 'C296_PRIVATE_JOURNEY_REFLECTION_B', 'C296_PRIVATE_JOURNEY_INTENTION_B');

INSERT INTO public.daily_deed_completions (user_id, daily_light_id, status)
VALUES
  ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000401', 'completed'),
  ('00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-000000000401', 'completed');

INSERT INTO public.daily_reminder_preferences (user_id, daily_enabled, reminder_time, timezone)
VALUES
  ('00000000-0000-4000-8000-000000000101', true, '07:15', 'America/Los_Angeles'),
  ('00000000-0000-4000-8000-000000000102', true, '08:45', 'Europe/Paris');

UPDATE public.newsletter_preferences
SET weekly_enabled = true, consented_at = now(), consent_source = 'settings'
WHERE user_id IN (
  '00000000-0000-4000-8000-000000000101',
  '00000000-0000-4000-8000-000000000102'
);

INSERT INTO public.invitation_links (id, inviter_user_id, code)
VALUES
  ('00000000-0000-4000-8000-000000000501', '00000000-0000-4000-8000-000000000101', 'a10000000000000000000000000000000001'),
  ('00000000-0000-4000-8000-000000000502', '00000000-0000-4000-8000-000000000102', 'b20000000000000000000000000000000002');

INSERT INTO public.invitation_acceptances (id, invitation_id, invited_user_id)
VALUES ('00000000-0000-4000-8000-000000000503', '00000000-0000-4000-8000-000000000501', '00000000-0000-4000-8000-000000000102');

DO $$
BEGIN
  IF (SELECT count(*) FROM auth.users WHERE id IN (
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000102',
    '00000000-0000-4000-8000-000000000103',
    '00000000-0000-4000-8000-000000000104'
  )) <> 4 THEN
    RAISE EXCEPTION 'C296 fixture users were not created.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.daily_reflections
    WHERE user_id = '00000000-0000-4000-8000-000000000101'
      AND reflection_text = 'C296_PRIVATE_DAILY_REFLECTION_SENTINEL'
  ) THEN
    RAISE EXCEPTION 'Private Daily reflection fixture was not created.';
  END IF;
END
$$;

-- Anonymous callers must be able to read public projections, but no private
-- base tables, internal moderation records, or admin-only RPCs.
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claim.sub', '', true);

DO $$
DECLARE
  v_row jsonb;
  v_payload text;
  v_denied boolean;
BEGIN
  IF current_user <> 'anon' THEN
    RAISE EXCEPTION 'Anonymous assertions are not running as anon.';
  END IF;

  SELECT to_jsonb(op)
  INTO v_row
  FROM public.offerings_public op
  WHERE op.id = '00000000-0000-4000-8000-000000000201';

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'Anonymous caller cannot read the public Offering projection.';
  END IF;

  IF v_row->>'user_id' IS NOT NULL
     OR v_row->>'author_name' IS NOT NULL
     OR v_row->>'author_username' IS NOT NULL THEN
    RAISE EXCEPTION 'Anonymous Offering identity was not fully masked: %', v_row;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.offerings_public WHERE user_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Public Offering projection exposes an internal member UUID.';
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(op))::text, '')
  INTO v_payload
  FROM public.offerings_public op;

  IF position('00000000-0000-4000-8000-000000000101' in v_payload) > 0
     OR position('00000000-0000-4000-8000-000000000102' in v_payload) > 0
     OR position('00000000-0000-4000-8000-000000000103' in v_payload) > 0
     OR position('00000000-0000-4000-8000-000000000104' in v_payload) > 0 THEN
    RAISE EXCEPTION 'Public Offering projection contains an internal account UUID.';
  END IF;

  SELECT to_jsonb(pp)
  INTO v_row
  FROM public.profiles_public pp
  WHERE pp.username = 'public-member';

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'Opted-in public profile is missing from profiles_public.';
  END IF;

  IF v_row ? 'user_id' OR v_row ? 'id' OR v_row ? 'email' THEN
    RAISE EXCEPTION 'Public profile projection contains private identity columns: %', v_row;
  END IF;

  IF position('00000000-0000-4000-8000-000000000101' in v_row::text) > 0
     OR position('00000000-0000-4000-8000-000000000102' in v_row::text) > 0
     OR position('00000000-0000-4000-8000-000000000103' in v_row::text) > 0
     OR position('00000000-0000-4000-8000-000000000104' in v_row::text) > 0 THEN
    RAISE EXCEPTION 'Public profile projection contains an internal account UUID.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.profiles_public
    WHERE username IN ('private-member', 'suspended-member', 'admin-member')
  ) THEN
    RAISE EXCEPTION 'Private or suspended profile escaped public-profile filtering.';
  END IF;

  v_denied := false;
  BEGIN
    PERFORM 1 FROM public.offerings LIMIT 1;
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'anon unexpectedly has direct access to public.offerings.';
  END IF;

  v_denied := false;
  BEGIN
    PERFORM 1 FROM public.profiles LIMIT 1;
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'anon unexpectedly has direct access to public.profiles.';
  END IF;

  v_denied := false;
  BEGIN
    PERFORM 1 FROM public.member_moderation_events LIMIT 1;
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'anon unexpectedly has direct access to moderation history.';
  END IF;

  v_denied := false;
  BEGIN
    PERFORM public.admin_get_member_context(
      '00000000-0000-4000-8000-000000000101'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'anon unexpectedly executed admin_get_member_context.';
  END IF;

  SELECT to_jsonb(op) INTO v_row FROM public.offerings_public op
  WHERE op.id='00000000-0000-4000-8000-000000000202';
  IF v_row->>'user_id' IS NOT NULL
     OR v_row->>'author_name' <> 'Public Member'
     OR v_row->>'author_username' <> 'public-member' THEN
    RAISE EXCEPTION 'Opted-in Offering attribution projection is incorrect: %', v_row;
  END IF;
  SELECT to_jsonb(op) INTO v_row FROM public.offerings_public op
  WHERE op.id='00000000-0000-4000-8000-000000000205';
  IF v_row->>'user_id' IS NOT NULL
     OR v_row->>'author_name' IS NOT NULL
     OR v_row->>'author_username' IS NOT NULL THEN
    RAISE EXCEPTION 'Suspended member identity escaped public Offering projection: %', v_row;
  END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(op))::text, '') INTO v_payload
  FROM public.offerings_public op;
  IF position('C296_INTERNAL_MODERATION_NOTE_SENTINEL' in v_payload)>0
     OR position('C296_MODERATOR_HIDDEN_SENTINEL' in v_payload)>0
     OR position('privacy-test.invalid' in v_payload)>0 THEN
    RAISE EXCEPTION 'Public Offering projection contains moderation or private account data.';
  END IF;

END
$$;

RESET ROLE;

-- Member B sees only their own Saved Lights and reactions.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000102', true);

DO $$
DECLARE
  v_count integer;
  v_rows bigint;
BEGIN
  IF current_user <> 'authenticated'
     OR auth.uid() <> '00000000-0000-4000-8000-000000000102'::uuid THEN
    RAISE EXCEPTION 'Member B assertions are not running under the expected identity.';
  END IF;

  SELECT count(*) INTO v_count FROM public.saved_lights;
  IF v_count <> 1 OR EXISTS (
    SELECT 1 FROM public.saved_lights
    WHERE user_id = '00000000-0000-4000-8000-000000000101'
  ) THEN
    RAISE EXCEPTION 'Member B can see another member''s Saved Lights.';
  END IF;

  SELECT count(*) INTO v_count
  FROM public.reactions
  WHERE id = '00000000-0000-4000-8000-000000000303';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Member B cannot read their own reaction.';
  END IF;

  DELETE FROM public.saved_lights
  WHERE id = '00000000-0000-4000-8000-000000000301';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'Member B deleted another member''s Saved Light.';
  END IF;
END
$$;

RESET ROLE;

-- Member A cannot inspect or mutate Member B's private activity, cannot write
-- reactions as another user, and can only remove/restore their own eligible
-- Offering through the guarded RPCs.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000101', true);

DO $$
DECLARE
  v_count integer;
  v_rows bigint;
  v_denied boolean;
  v_status text;
  v_removed_at timestamptz;
  v_payload text;
BEGIN
  IF current_user <> 'authenticated'
     OR auth.uid() <> '00000000-0000-4000-8000-000000000101'::uuid THEN
    RAISE EXCEPTION 'Member A assertions are not running under the expected identity.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.offerings
    WHERE user_id <> auth.uid()
  ) THEN
    RAISE EXCEPTION 'Authenticated member can read another member''s private Offering base row.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.offerings
    WHERE id = '00000000-0000-4000-8000-000000000201'
      AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Member A lost access to their own Offering base row.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.profiles
    WHERE user_id <> auth.uid()
  ) THEN
    RAISE EXCEPTION 'Authenticated member can read another member''s private profile row.';
  END IF;

  SELECT count(*) INTO v_count FROM public.saved_lights;
  IF v_count <> 1 OR EXISTS (
    SELECT 1 FROM public.saved_lights
    WHERE user_id = '00000000-0000-4000-8000-000000000102'
  ) THEN
    RAISE EXCEPTION 'Member A can see another member''s Saved Lights.';
  END IF;

  DELETE FROM public.saved_lights
  WHERE id = '00000000-0000-4000-8000-000000000302';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'Member A deleted Member B''s Saved Light.';
  END IF;

  v_denied := false;
  BEGIN
    INSERT INTO public.saved_lights (id, user_id, offering_id)
    VALUES (
      '00000000-0000-4000-8000-000000000307',
      '00000000-0000-4000-8000-000000000102',
      '00000000-0000-4000-8000-000000000201'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Member A inserted a Saved Light owned by Member B.';
  END IF;

  v_denied := false;
  BEGIN
    UPDATE public.saved_lights
    SET user_id = '00000000-0000-4000-8000-000000000102'
    WHERE id = '00000000-0000-4000-8000-000000000301';
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Authenticated member unexpectedly updated an immutable Saved Light.';
  END IF;

  SELECT count(*) INTO v_count
  FROM public.reactions
  WHERE id = '00000000-0000-4000-8000-000000000303';
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Member A can read Member B''s private reaction row.';
  END IF;

  DELETE FROM public.reactions
  WHERE id = '00000000-0000-4000-8000-000000000303';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'Member A deleted Member B''s reaction.';
  END IF;

  v_denied := false;
  BEGIN
    INSERT INTO public.reactions (id, offering_id, user_id, reaction_type)
    VALUES (
      '00000000-0000-4000-8000-000000000308',
      '00000000-0000-4000-8000-000000000202',
      '00000000-0000-4000-8000-000000000102',
      'inspired_me'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Member A inserted a reaction under Member B''s identity.';
  END IF;

  INSERT INTO public.reactions (id, offering_id, user_id, reaction_type)
  VALUES (
    '00000000-0000-4000-8000-000000000309',
    '00000000-0000-4000-8000-000000000202',
    '00000000-0000-4000-8000-000000000101',
    'inspired_me'
  );

  DELETE FROM public.reactions
  WHERE id = '00000000-0000-4000-8000-000000000309';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Member A could not remove their own reaction.';
  END IF;

  v_denied := false;
  BEGIN
    PERFORM public.remove_own_offering(
      '00000000-0000-4000-8000-000000000202'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Member A removed Member B''s Offering.';
  END IF;

  PERFORM public.remove_own_offering(
    '00000000-0000-4000-8000-000000000201'
  );

  SELECT status, owner_removed_at
  INTO v_status, v_removed_at
  FROM public.offerings
  WHERE id = '00000000-0000-4000-8000-000000000201';

  IF v_status <> 'hidden' OR v_removed_at IS NULL THEN
    RAISE EXCEPTION 'Owner removal did not hide Member A''s Offering.';
  END IF;

  v_denied := false;
  BEGIN
    PERFORM public.restore_own_offering(
      '00000000-0000-4000-8000-000000000202'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Member A restored Member B''s Offering.';
  END IF;

  PERFORM public.restore_own_offering(
    '00000000-0000-4000-8000-000000000201'
  );

  SELECT status, owner_removed_at
  INTO v_status, v_removed_at
  FROM public.offerings
  WHERE id = '00000000-0000-4000-8000-000000000201';

  IF v_status <> 'pending' OR v_removed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Owner restore did not return the Offering to moderation review.';
  END IF;

  v_denied := false;
  BEGIN
    PERFORM public.remove_own_offering(
      '00000000-0000-4000-8000-000000000203'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Owner removal bypassed the rejected-Offering guard.';
  END IF;

  v_denied := false;
  BEGIN
    DELETE FROM public.offerings
    WHERE id = '00000000-0000-4000-8000-000000000201';
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Authenticated member unexpectedly has direct Offering DELETE privilege.';
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(op))::text, '')
  INTO v_payload
  FROM public.offerings_public op;

  IF position('00000000-0000-4000-8000-000000000101' in v_payload) > 0
     OR position('00000000-0000-4000-8000-000000000102' in v_payload) > 0
     OR position('00000000-0000-4000-8000-000000000103' in v_payload) > 0
     OR position('00000000-0000-4000-8000-000000000104' in v_payload) > 0 THEN
    RAISE EXCEPTION 'Authenticated public Offering projection contains an internal account UUID.';
  END IF;

  v_denied := false;
  BEGIN
    PERFORM public.admin_get_member_context(
      '00000000-0000-4000-8000-000000000101'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Ordinary authenticated member accessed internal moderation context.';
  END IF;

  v_denied := false;
  BEGIN
    PERFORM 1 FROM public.member_moderation_events LIMIT 1;
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Ordinary authenticated member read internal moderation history directly.';
  END IF;

  DELETE FROM public.saved_lights
  WHERE id = '00000000-0000-4000-8000-000000000301';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Member A could not remove their own Saved Light.';
  END IF;
END
$$;

RESET ROLE;

-- A suspended member cannot react, but can still remove their own content for
-- privacy/safety. Restore remains unavailable until the account is active.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000103', true);

DO $$
DECLARE
  v_denied boolean;
  v_status text;
  v_removed_at timestamptz;
BEGIN
  v_denied := false;
  BEGIN
    INSERT INTO public.reactions (id, offering_id, user_id, reaction_type)
    VALUES (
      '00000000-0000-4000-8000-000000000310',
      '00000000-0000-4000-8000-000000000202',
      '00000000-0000-4000-8000-000000000103',
      'bless'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Suspended member inserted a community reaction.';
  END IF;

  PERFORM public.remove_own_offering(
    '00000000-0000-4000-8000-000000000205'
  );

  SELECT status, owner_removed_at
  INTO v_status, v_removed_at
  FROM public.offerings
  WHERE id = '00000000-0000-4000-8000-000000000205';

  IF v_status <> 'hidden' OR v_removed_at IS NULL THEN
    RAISE EXCEPTION 'Suspended member could not remove their own Offering.';
  END IF;

  v_denied := false;
  BEGIN
    PERFORM public.restore_own_offering(
      '00000000-0000-4000-8000-000000000205'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Suspended member restored an Offering to moderation.';
  END IF;
END
$$;

RESET ROLE;

-- Member B can remove and restore their own Offering; the operation remains a
-- moderation resubmission, not a direct public republish.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000102', true);

DO $$
DECLARE
  v_count integer;
  v_rows bigint;
  v_status text;
  v_removed_at timestamptz;
  v_denied boolean;
BEGIN
  SELECT count(*) INTO v_count FROM public.saved_lights;
  IF v_count <> 1 OR EXISTS (
    SELECT 1 FROM public.saved_lights
    WHERE user_id = '00000000-0000-4000-8000-000000000101'
  ) THEN
    RAISE EXCEPTION 'Member B Saved Lights isolation changed after Member A removal.';
  END IF;

  v_denied := false;
  BEGIN
    PERFORM public.remove_own_offering(
      '00000000-0000-4000-8000-000000000204'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Owner removal changed a moderator-hidden Offering.';
  END IF;

  v_denied := false;
  BEGIN
    PERFORM public.restore_own_offering(
      '00000000-0000-4000-8000-000000000204'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Owner restore bypassed a moderator-hidden Offering.';
  END IF;

  PERFORM public.remove_own_offering(
    '00000000-0000-4000-8000-000000000202'
  );

  SELECT status, owner_removed_at
  INTO v_status, v_removed_at
  FROM public.offerings
  WHERE id = '00000000-0000-4000-8000-000000000202';

  IF v_status <> 'hidden' OR v_removed_at IS NULL THEN
    RAISE EXCEPTION 'Member B could not remove their own Offering.';
  END IF;

  PERFORM public.restore_own_offering(
    '00000000-0000-4000-8000-000000000202'
  );

  SELECT status, owner_removed_at
  INTO v_status, v_removed_at
  FROM public.offerings
  WHERE id = '00000000-0000-4000-8000-000000000202';

  IF v_status <> 'pending' OR v_removed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Member B restore bypassed moderation review.';
  END IF;
END
$$;

RESET ROLE;

-- Only an active database-role admin can read internal moderation context.
-- The narrow RPC returns moderation data but deliberately excludes private
-- Offering and Daily reflection text.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000104', true);

DO $$
DECLARE
  v_context jsonb;
  v_denied boolean;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Active database admin fixture was not recognized as admin.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.offerings
    WHERE id = '00000000-0000-4000-8000-000000000202'
  ) THEN
    RAISE EXCEPTION 'Database admin lost access to internal Offering moderation rows.';
  END IF;

  v_context := public.admin_get_member_context(
    '00000000-0000-4000-8000-000000000101'
  );

  IF v_context->'profile'->>'display_name' <> 'Private Member' THEN
    RAISE EXCEPTION 'Admin context did not return the intended private member profile.';
  END IF;

  IF position('C296_INTERNAL_MODERATION_NOTE_SENTINEL' in v_context::text) = 0
     OR position('C296_INTERNAL_REPORT_DETAILS_SENTINEL' in v_context::text) = 0
     OR position('C296_INTERNAL_REPORT_ADMIN_NOTE_SENTINEL' in v_context::text) = 0
     OR position('C296_INTERNAL_MODERATION_EVENT_SENTINEL' in v_context::text) = 0 THEN
    RAISE EXCEPTION 'Admin context is missing expected internal moderation data.';
  END IF;

  IF position('C296_PRIVATE_OFFERING_REFLECTION_SENTINEL' in v_context::text) > 0
     OR position('C296_PRIVATE_DAILY_REFLECTION_SENTINEL' in v_context::text) > 0 THEN
    RAISE EXCEPTION 'Admin moderation context exposed private reflection text.';
  END IF;

  v_denied := false;
  BEGIN
    PERFORM 1 FROM public.member_moderation_events LIMIT 1;
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Admin unexpectedly bypassed the narrow moderation-context RPC.';
  END IF;
END
$$;


-- C332: verify current Journey and private member-data isolation under real database roles.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000102', true);
DO $$
DECLARE v_denied boolean;
BEGIN
  IF (SELECT count(*) FROM public.daily_reflections WHERE daily_light_id='00000000-0000-4000-8000-000000000401') <> 1
     OR EXISTS (SELECT 1 FROM public.daily_reflections WHERE daily_light_id='00000000-0000-4000-8000-000000000401' AND user_id='00000000-0000-4000-8000-000000000101') THEN
    RAISE EXCEPTION 'Member B read another member''s private Daily reflection/Journey.';
  END IF;
  IF (SELECT count(*) FROM public.daily_deed_completions WHERE daily_light_id='00000000-0000-4000-8000-000000000401') <> 1
     OR EXISTS (SELECT 1 FROM public.daily_deed_completions WHERE daily_light_id='00000000-0000-4000-8000-000000000401' AND user_id='00000000-0000-4000-8000-000000000101') THEN
    RAISE EXCEPTION 'Member B read another member''s private Journey completion.';
  END IF;
  IF (SELECT count(*) FROM public.daily_reminder_preferences) <> 1
     OR NOT EXISTS (SELECT 1 FROM public.daily_reminder_preferences WHERE user_id=auth.uid() AND timezone='Europe/Paris') THEN
    RAISE EXCEPTION 'Member B reminder preferences are not isolated to their own row.';
  END IF;
  IF (SELECT count(*) FROM public.newsletter_preferences) <> 1
     OR NOT EXISTS (SELECT 1 FROM public.newsletter_preferences WHERE user_id=auth.uid() AND weekly_enabled) THEN
    RAISE EXCEPTION 'Member B newsletter preferences are not isolated to their own row.';
  END IF;
  IF (SELECT count(*) FROM public.invitation_links) <> 1
     OR NOT EXISTS (SELECT 1 FROM public.invitation_links WHERE inviter_user_id=auth.uid() AND code='b20000000000000000000000000000000002') THEN
    RAISE EXCEPTION 'Member B invitation links are not isolated to their own row.';
  END IF;
  v_denied := false;
  BEGIN PERFORM 1 FROM public.reflections WHERE id='00000000-0000-4000-8000-000000000306';
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  IF NOT v_denied THEN RAISE EXCEPTION 'Member B directly accessed private Offering reflection records.'; END IF;
  v_denied := false;
  BEGIN PERFORM 1 FROM public.invitation_acceptances LIMIT 1;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  IF NOT v_denied THEN RAISE EXCEPTION 'Member B read private invitation attribution.'; END IF;
  v_denied := false;
  BEGIN PERFORM 1 FROM public.member_moderation_events LIMIT 1;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  IF NOT v_denied THEN RAISE EXCEPTION 'Member B read internal moderation history.'; END IF;
  v_denied := false;
  BEGIN PERFORM 1 FROM public.admin_list_members('all');
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  IF NOT v_denied THEN RAISE EXCEPTION 'Ordinary member executed admin_list_members.'; END IF;
  v_denied := false;
  BEGIN PERFORM public.set_member_suspension('00000000-0000-4000-8000-000000000103', true, 'Unauthorized member moderation attempt');
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  IF NOT v_denied THEN RAISE EXCEPTION 'Ordinary member executed set_member_suspension.'; END IF;
  v_denied := false;
  BEGIN PERFORM public.record_invitation_acceptance('00000000-0000-4000-8000-000000000102', 'a10000000000000000000000000000000001');
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  IF NOT v_denied THEN RAISE EXCEPTION 'Ordinary member executed private invitation attribution RPC.'; END IF;
END
$$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000101', true);
DO $$
DECLARE v_denied boolean;
BEGIN
  IF (SELECT count(*) FROM public.daily_reflections WHERE daily_light_id='00000000-0000-4000-8000-000000000401') <> 1
     OR EXISTS (SELECT 1 FROM public.daily_reflections WHERE daily_light_id='00000000-0000-4000-8000-000000000401' AND user_id='00000000-0000-4000-8000-000000000102') THEN
    RAISE EXCEPTION 'Member A cannot isolate their private Daily reflection/Journey.';
  END IF;
  IF (SELECT count(*) FROM public.daily_deed_completions WHERE daily_light_id='00000000-0000-4000-8000-000000000401') <> 1
     OR EXISTS (SELECT 1 FROM public.daily_deed_completions WHERE daily_light_id='00000000-0000-4000-8000-000000000401' AND user_id='00000000-0000-4000-8000-000000000102') THEN
    RAISE EXCEPTION 'Member A cannot isolate their private Journey completion.';
  END IF;
  IF (SELECT count(*) FROM public.daily_reminder_preferences) <> 1
     OR NOT EXISTS (SELECT 1 FROM public.daily_reminder_preferences WHERE user_id=auth.uid() AND timezone='America/Los_Angeles') THEN
    RAISE EXCEPTION 'Member A reminder preferences are not isolated to their own row.';
  END IF;
  IF (SELECT count(*) FROM public.newsletter_preferences) <> 1
     OR NOT EXISTS (SELECT 1 FROM public.newsletter_preferences WHERE user_id=auth.uid() AND weekly_enabled) THEN
    RAISE EXCEPTION 'Member A newsletter preferences are not isolated to their own row.';
  END IF;
  IF (SELECT count(*) FROM public.invitation_links) <> 1
     OR NOT EXISTS (SELECT 1 FROM public.invitation_links WHERE inviter_user_id=auth.uid() AND code='a10000000000000000000000000000000001') THEN
    RAISE EXCEPTION 'Member A invitation links are not isolated to their own row.';
  END IF;
  v_denied := false;
  BEGIN PERFORM 1 FROM public.invitation_acceptances LIMIT 1;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  IF NOT v_denied THEN RAISE EXCEPTION 'Member A read private invitation attribution.'; END IF;
END
$$;
RESET ROLE;

-- An active database administrator may use narrow moderation APIs, but not private Journey/preferences/attribution.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000104', true);
DO $$
DECLARE v_members bigint; v_context jsonb; v_denied boolean; v_member_list text;
BEGIN
  SELECT count(*) INTO v_members FROM public.admin_list_members('all')
  WHERE member_user_id='00000000-0000-4000-8000-000000000101';
  IF v_members <> 1 THEN RAISE EXCEPTION 'Authorized admin could not use admin_list_members.'; END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(m))::text, '') INTO v_member_list FROM public.admin_list_members('all') m;
  IF position('privacy-test.invalid' in v_member_list)>0 THEN RAISE EXCEPTION 'Admin member list exposed email addresses.'; END IF;
  v_context := public.admin_get_member_context('00000000-0000-4000-8000-000000000101');
  IF v_context IS NULL OR position('C296_INTERNAL_MODERATION_EVENT_SENTINEL' in v_context::text)=0 THEN
    RAISE EXCEPTION 'Authorized admin moderation context is missing internal evidence.';
  END IF;
  IF position('C296_PRIVATE_JOURNEY_REFLECTION_A' in v_context::text)>0
     OR position('C296_PRIVATE_JOURNEY_INTENTION_A' in v_context::text)>0
     OR position('C296_PRIVATE_OFFERING_REFLECTION_SENTINEL' in v_context::text)>0
     OR position('America/Los_Angeles' in v_context::text)>0
     OR position('a10000000000000000000000000000000001' in v_context::text)>0
     OR position('private-member@privacy-test.invalid' in v_context::text)>0 THEN
    RAISE EXCEPTION 'Admin moderation context exposed private reflections or member preference/attribution data.';
  END IF;
  IF (SELECT count(*) FROM public.daily_deed_completions) <> 0
     OR (SELECT count(*) FROM public.daily_reminder_preferences) <> 0
     OR (SELECT count(*) FROM public.newsletter_preferences) <> 1
     OR NOT EXISTS (SELECT 1 FROM public.newsletter_preferences WHERE user_id=auth.uid())
     OR (SELECT count(*) FROM public.invitation_links) <> 0 THEN
    RAISE EXCEPTION 'Administrator role accessed another member''s private Journey, reminder, newsletter, or invitation data.';
  END IF;
  v_denied := false;
  BEGIN PERFORM 1 FROM public.member_moderation_events LIMIT 1;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  IF NOT v_denied THEN RAISE EXCEPTION 'Admin bypassed the narrow moderation RPC boundary.'; END IF;
  v_denied := false;
  BEGIN PERFORM 1 FROM public.reflections LIMIT 1;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  IF NOT v_denied THEN RAISE EXCEPTION 'Admin directly accessed private Offering reflection records outside the moderation context.'; END IF;
  v_denied := false;
  BEGIN PERFORM 1 FROM public.invitation_acceptances LIMIT 1;
  EXCEPTION WHEN insufficient_privilege THEN v_denied := true; END;
  IF NOT v_denied THEN RAISE EXCEPTION 'Admin read private invitation attribution directly.'; END IF;
END
$$;

ROLLBACK;

\echo 'Privacy and authorization database behavior assertions PASS'
