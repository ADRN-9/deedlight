\set ON_ERROR_STOP on

BEGIN;

-- Migration 023 must have removed the historical broad-read policy. The
-- synthetic owner can still read their own Offering, but not the other
-- member's approved row or its internal moderation note.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000110', true);

DO $$
DECLARE
  v_count integer;
BEGIN
  IF current_user <> 'authenticated'
     OR auth.uid() <> '00000000-0000-4000-8000-000000000110'::uuid THEN
    RAISE EXCEPTION 'Post-migration legacy policy assertions have the wrong caller.';
  END IF;

  SELECT count(*) INTO v_count
  FROM public.offerings
  WHERE id = '00000000-0000-4000-8000-000000000210';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Migration 023 removed legitimate owner access to the legacy Offering.';
  END IF;

  SELECT count(*) INTO v_count
  FROM public.offerings
  WHERE id = '00000000-0000-4000-8000-000000000211'
     OR moderation_note = 'C300_LEGACY_MODERATION_NOTE_SENTINEL';
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Migration 023 left cross-member access to the legacy Offering or moderation note.';
  END IF;
END
$$;

RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);

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
    role = 'admin',
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

INSERT INTO public.daily_posts (
  date, slug, title, reflection, daily_action, status, published_at
)
VALUES (
  current_date + 1,
  'c300-privacy-test-owner-write-daily-post',
  'C300 private reflection owner-write fixture',
  'Synthetic Daily post used only to test owner-authorized reflection writes.',
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

INSERT INTO public.daily_lights (
  id, scheduled_date, status, title, summary, small_deed, reflection_prompt
)
VALUES (
  '00000000-0000-4000-8000-000000000206',
  current_date + 365,
  'published',
  'C298 privacy Journey fixture',
  'Synthetic Daily Light used only by the privacy database regression suite.',
  'No action; this row exists only inside the test transaction.',
  'What mattered today?'
);

INSERT INTO public.daily_lights (
  id, scheduled_date, status, title, summary, small_deed, reflection_prompt
)
VALUES (
  '00000000-0000-4000-8000-000000000207',
  current_date + 366,
  'published',
  'C300 Journey owner-write fixture',
  'Synthetic Daily Light used only by the privacy database regression suite.',
  'No action; this fixture exists only inside the test transaction.',
  'What mattered today?'
);

UPDATE public.daily_reflections
SET daily_light_id = '00000000-0000-4000-8000-000000000206',
    reflection = 'C298_PRIVATE_DAILY_LIGHT_REFLECTION_MEMBER_A_SENTINEL',
    intention = 'C298_PRIVATE_DAILY_INTENTION_MEMBER_A_SENTINEL'
WHERE user_id = '00000000-0000-4000-8000-000000000101'
  AND reflection_text = 'C296_PRIVATE_DAILY_REFLECTION_SENTINEL';

INSERT INTO public.daily_reflections (
  user_id, daily_post_id, daily_light_id, reflection_text,
  reflection, intention, is_private
)
SELECT
  '00000000-0000-4000-8000-000000000102',
  dp.id,
  '00000000-0000-4000-8000-000000000206',
  'C298_PRIVATE_DAILY_REFLECTION_MEMBER_B_SENTINEL',
  'C298_PRIVATE_DAILY_LIGHT_REFLECTION_MEMBER_B_SENTINEL',
  'C298_PRIVATE_DAILY_INTENTION_MEMBER_B_SENTINEL',
  true
FROM public.daily_posts dp
WHERE dp.slug = 'c296-privacy-test-daily-post';

INSERT INTO public.daily_deed_completions (
  id, user_id, daily_light_id, status
)
VALUES
  (
    '00000000-0000-4000-8000-000000000311',
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000206',
    'completed'
  ),
  (
    '00000000-0000-4000-8000-000000000312',
    '00000000-0000-4000-8000-000000000102',
    '00000000-0000-4000-8000-000000000206',
    'completed'
  );

INSERT INTO public.weekly_goodness_features (
  week_start, offering_id, selected_by
)
VALUES (
  date_trunc('week', timezone('UTC', now()))::date,
  '00000000-0000-4000-8000-000000000201',
  '00000000-0000-4000-8000-000000000104'
);

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
      AND reflection = 'C298_PRIVATE_DAILY_LIGHT_REFLECTION_MEMBER_A_SENTINEL'
  ) THEN
    RAISE EXCEPTION 'Private Daily reflection fixture was not created.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.daily_reflections
    WHERE user_id = '00000000-0000-4000-8000-000000000102'
      AND reflection_text = 'C298_PRIVATE_DAILY_REFLECTION_MEMBER_B_SENTINEL'
      AND reflection = 'C298_PRIVATE_DAILY_LIGHT_REFLECTION_MEMBER_B_SENTINEL'
  ) THEN
    RAISE EXCEPTION 'Member B private Daily reflection fixture was not created.';
  END IF;

  IF (SELECT count(*) FROM public.daily_deed_completions
      WHERE id IN (
        '00000000-0000-4000-8000-000000000311',
        '00000000-0000-4000-8000-000000000312'
      )) <> 2 THEN
    RAISE EXCEPTION 'Two-member private Journey fixtures were not created.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.weekly_goodness_features
    WHERE offering_id = '00000000-0000-4000-8000-000000000201'
      AND week_start = date_trunc('week', timezone('UTC', now()))::date
  ) THEN
    RAISE EXCEPTION 'Current Weekly Goodness feature fixture was not created.';
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

  SELECT to_jsonb(op)
  INTO v_row
  FROM public.offerings_public op
  WHERE op.id = '00000000-0000-4000-8000-000000000202';

  IF v_row IS NULL
     OR v_row->>'user_id' IS NOT NULL
     OR v_row->>'author_name' <> 'Public Member'
     OR v_row->>'author_username' <> 'public-member' THEN
    RAISE EXCEPTION 'Non-anonymous public Offering attribution is missing or exposes an internal UUID: %', v_row;
  END IF;

  SELECT to_jsonb(rising)
  INTO v_row
  FROM public.offerings_rising rising
  WHERE rising.id = '00000000-0000-4000-8000-000000000201';

  IF v_row IS NULL
     OR v_row->>'user_id' IS NOT NULL
     OR v_row->>'author_name' IS NOT NULL
     OR v_row->>'author_username' IS NOT NULL THEN
    RAISE EXCEPTION 'Rising Offering projection did not preserve anonymous identity masking: %', v_row;
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(rising))::text, '')
  INTO v_payload
  FROM public.offerings_rising rising;

  IF position('00000000-0000-4000-8000-000000000101' in v_payload) > 0
     OR position('00000000-0000-4000-8000-000000000102' in v_payload) > 0
     OR position('00000000-0000-4000-8000-000000000103' in v_payload) > 0
     OR position('00000000-0000-4000-8000-000000000104' in v_payload) > 0 THEN
    RAISE EXCEPTION 'Public Rising Offering projection contains an internal account UUID.';
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

  SELECT to_jsonb(weekly)
  INTO v_row
  FROM public.get_weekly_goodness(24) weekly
  WHERE weekly.id = '00000000-0000-4000-8000-000000000201';

  IF v_row IS NULL
     OR v_row ? 'user_id'
     OR v_row->>'author_name' IS NOT NULL
     OR v_row->>'author_username' IS NOT NULL
     OR position('00000000-0000-4000-8000-000000000101' in v_row::text) > 0
     OR position('00000000-0000-4000-8000-000000000102' in v_row::text) > 0
     OR position('00000000-0000-4000-8000-000000000103' in v_row::text) > 0
     OR position('00000000-0000-4000-8000-000000000104' in v_row::text) > 0 THEN
    RAISE EXCEPTION 'get_weekly_goodness exposed anonymous Offering identity or an account UUID: %', v_row;
  END IF;

  SELECT to_jsonb(feature)
  INTO v_row
  FROM public.get_current_weekly_goodness_feature() feature
  WHERE feature.id = '00000000-0000-4000-8000-000000000201';

  IF v_row IS NULL
     OR v_row ? 'user_id'
     OR v_row->>'author_name' IS NOT NULL
     OR v_row->>'author_username' IS NOT NULL
     OR position('00000000-0000-4000-8000-000000000101' in v_row::text) > 0
     OR position('00000000-0000-4000-8000-000000000102' in v_row::text) > 0
     OR position('00000000-0000-4000-8000-000000000103' in v_row::text) > 0
     OR position('00000000-0000-4000-8000-000000000104' in v_row::text) > 0 THEN
    RAISE EXCEPTION 'get_current_weekly_goodness_feature exposed anonymous Offering identity or an account UUID: %', v_row;
  END IF;

  SELECT to_jsonb(completions)
  INTO v_row
  FROM public.daily_deed_completion_counts completions
  WHERE completions.daily_light_id = '00000000-0000-4000-8000-000000000206';

  IF v_row IS NULL
     OR v_row ? 'user_id'
     OR v_row->>'completion_count' <> '2' THEN
    RAISE EXCEPTION 'Public Journey aggregate exposed private completion rows or lost its aggregate: %', v_row;
  END IF;

  v_denied := false;
  BEGIN
    PERFORM 1 FROM public.daily_reflections LIMIT 1;
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'anon unexpectedly has direct access to private Daily reflections.';
  END IF;

  v_denied := false;
  BEGIN
    PERFORM 1 FROM public.daily_deed_completions LIMIT 1;
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'anon unexpectedly has direct access to private Journey records.';
  END IF;

  v_denied := false;
  BEGIN
    PERFORM 1 FROM public.weekly_goodness_features LIMIT 1;
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'anon unexpectedly has direct access to private Weekly Goodness curation.';
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

  SELECT count(*) INTO v_count FROM public.daily_reflections;
  IF v_count <> 1 OR EXISTS (
    SELECT 1 FROM public.daily_reflections WHERE user_id <> auth.uid()
  ) OR NOT EXISTS (
    SELECT 1 FROM public.daily_reflections
    WHERE user_id = auth.uid()
      AND reflection_text = 'C298_PRIVATE_DAILY_REFLECTION_MEMBER_B_SENTINEL'
      AND reflection = 'C298_PRIVATE_DAILY_LIGHT_REFLECTION_MEMBER_B_SENTINEL'
      AND is_private = true
  ) THEN
    RAISE EXCEPTION 'Member B cannot read only their own private Daily reflection.';
  END IF;

  SELECT count(*) INTO v_count FROM public.daily_deed_completions;
  IF v_count <> 1 OR EXISTS (
    SELECT 1 FROM public.daily_deed_completions WHERE user_id <> auth.uid()
  ) OR NOT EXISTS (
    SELECT 1 FROM public.daily_deed_completions
    WHERE id = '00000000-0000-4000-8000-000000000312'
      AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Member B cannot read only their own private Journey record.';
  END IF;

  DELETE FROM public.daily_deed_completions
  WHERE id = '00000000-0000-4000-8000-000000000311';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'Member B deleted Member A''s private Journey record.';
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

  SELECT count(*) INTO v_count FROM public.daily_reflections;
  IF v_count <> 1 OR EXISTS (
    SELECT 1 FROM public.daily_reflections WHERE user_id <> auth.uid()
  ) OR NOT EXISTS (
    SELECT 1 FROM public.daily_reflections
    WHERE user_id = auth.uid()
      AND reflection_text = 'C296_PRIVATE_DAILY_REFLECTION_SENTINEL'
      AND reflection = 'C298_PRIVATE_DAILY_LIGHT_REFLECTION_MEMBER_A_SENTINEL'
      AND is_private = true
  ) THEN
    RAISE EXCEPTION 'Member A cannot read only their own private Daily reflection.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.daily_reflections
    WHERE reflection_text = 'C298_PRIVATE_DAILY_REFLECTION_MEMBER_B_SENTINEL'
       OR reflection = 'C298_PRIVATE_DAILY_LIGHT_REFLECTION_MEMBER_B_SENTINEL'
  ) THEN
    RAISE EXCEPTION 'Member A can read Member B''s private Daily reflection.';
  END IF;

  UPDATE public.daily_reflections
  SET reflection_text = 'C300_PRIVATE_DAILY_REFLECTION_OWNER_UPDATE_SENTINEL',
      reflection = 'C300_PRIVATE_DAILY_REFLECTION_OWNER_UPDATE_BODY_SENTINEL'
  WHERE user_id = auth.uid()
    AND reflection_text = 'C296_PRIVATE_DAILY_REFLECTION_SENTINEL';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Member A could not update their own private Daily reflection.';
  END IF;

  UPDATE public.daily_reflections
  SET reflection_text = 'C300_CROSS_MEMBER_REFLECTION_UPDATE_SHOULD_FAIL'
  WHERE reflection_text = 'C298_PRIVATE_DAILY_REFLECTION_MEMBER_B_SENTINEL';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'Member A updated another member''s private Daily reflection.';
  END IF;

  v_denied := false;
  BEGIN
    UPDATE public.daily_reflections
    SET user_id = '00000000-0000-4000-8000-000000000103'
    WHERE user_id = auth.uid()
      AND reflection_text = 'C300_PRIVATE_DAILY_REFLECTION_OWNER_UPDATE_SENTINEL';
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Member A changed the owner of an existing private Daily reflection.';
  END IF;

  v_denied := false;
  BEGIN
    INSERT INTO public.daily_reflections (
      user_id, daily_post_id, reflection_text, is_private
    )
    VALUES (
      '00000000-0000-4000-8000-000000000102',
      (SELECT id FROM public.daily_posts WHERE slug = 'c300-privacy-test-owner-write-daily-post'),
      'C300_CROSS_MEMBER_REFLECTION_INSERT_SHOULD_FAIL',
      true
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Member A inserted a private Daily reflection under Member B''s identity.';
  END IF;

  INSERT INTO public.daily_reflections (
    user_id, daily_post_id, reflection_text, is_private
  )
  VALUES (
    auth.uid(),
    (SELECT id FROM public.daily_posts WHERE slug = 'c300-privacy-test-owner-write-daily-post'),
    'C300_PRIVATE_DAILY_REFLECTION_OWNER_INSERT_SENTINEL',
    true
  );
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 OR NOT EXISTS (
    SELECT 1 FROM public.daily_reflections
    WHERE user_id = auth.uid()
      AND reflection_text = 'C300_PRIVATE_DAILY_REFLECTION_OWNER_INSERT_SENTINEL'
      AND is_private = true
  ) THEN
    RAISE EXCEPTION 'Member A could not insert their own private Daily reflection.';
  END IF;

  DELETE FROM public.daily_reflections
  WHERE user_id = '00000000-0000-4000-8000-000000000102'
    AND reflection_text = 'C298_PRIVATE_DAILY_REFLECTION_MEMBER_B_SENTINEL';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'Member A deleted another member''s private Daily reflection.';
  END IF;

  DELETE FROM public.daily_reflections
  WHERE user_id = auth.uid()
    AND reflection_text = 'C300_PRIVATE_DAILY_REFLECTION_OWNER_INSERT_SENTINEL';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 OR EXISTS (
    SELECT 1 FROM public.daily_reflections
    WHERE user_id = auth.uid()
      AND reflection_text = 'C300_PRIVATE_DAILY_REFLECTION_OWNER_INSERT_SENTINEL'
  ) THEN
    RAISE EXCEPTION 'Member A could not delete their own eligible private Daily reflection.';
  END IF;

  SELECT count(*) INTO v_count FROM public.daily_deed_completions;
  IF v_count <> 1 OR EXISTS (
    SELECT 1 FROM public.daily_deed_completions WHERE user_id <> auth.uid()
  ) OR NOT EXISTS (
    SELECT 1 FROM public.daily_deed_completions
    WHERE id = '00000000-0000-4000-8000-000000000311'
      AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Member A cannot read only their own private Journey record.';
  END IF;

  DELETE FROM public.daily_deed_completions
  WHERE id = '00000000-0000-4000-8000-000000000312';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'Member A deleted Member B''s private Journey record.';
  END IF;

  v_denied := false;
  BEGIN
    INSERT INTO public.daily_deed_completions (
      id, user_id, daily_light_id, status
    )
    VALUES (
      '00000000-0000-4000-8000-000000000313',
      '00000000-0000-4000-8000-000000000102',
      '00000000-0000-4000-8000-000000000207',
      'completed'
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Member A inserted a Journey record under Member B''s identity.';
  END IF;

  INSERT INTO public.daily_deed_completions (
    id, user_id, daily_light_id, status
  )
  VALUES (
    '00000000-0000-4000-8000-000000000314',
    auth.uid(),
    '00000000-0000-4000-8000-000000000207',
    'completed'
  );
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Member A could not insert their own Journey record.';
  END IF;

  DELETE FROM public.daily_deed_completions
  WHERE id = '00000000-0000-4000-8000-000000000314';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Member A could not delete their own Journey record.';
  END IF;

  SELECT count(*) INTO v_count FROM public.daily_deed_completions
  WHERE id = '00000000-0000-4000-8000-000000000314';
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Member A''s deleted Journey record remains visible.';
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
  IF public.is_admin() THEN
    RAISE EXCEPTION 'Suspended database admin retained administrative authority.';
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
    RAISE EXCEPTION 'Suspended database admin accessed internal moderation context.';
  END IF;

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
  v_count integer;
  v_rows bigint;
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
     OR position('C296_PRIVATE_DAILY_REFLECTION_SENTINEL' in v_context::text) > 0
     OR position('C298_PRIVATE_DAILY_LIGHT_REFLECTION_MEMBER_A_SENTINEL' in v_context::text) > 0
     OR position('C298_PRIVATE_DAILY_REFLECTION_MEMBER_B_SENTINEL' in v_context::text) > 0
     OR position('C298_PRIVATE_DAILY_LIGHT_REFLECTION_MEMBER_B_SENTINEL' in v_context::text) > 0
     OR position('C300_PRIVATE_DAILY_REFLECTION_OWNER_UPDATE_SENTINEL' in v_context::text) > 0
     OR position('C300_PRIVATE_DAILY_REFLECTION_OWNER_UPDATE_BODY_SENTINEL' in v_context::text) > 0
     OR position('C300_PRIVATE_DAILY_REFLECTION_OWNER_INSERT_SENTINEL' in v_context::text) > 0 THEN
    RAISE EXCEPTION 'Admin moderation context exposed private reflection text.';
  END IF;

  SELECT count(*) INTO v_count
  FROM public.daily_reflections
  WHERE user_id = '00000000-0000-4000-8000-000000000101';
  IF v_count <> 0 OR EXISTS (SELECT 1 FROM public.daily_reflections) THEN
    RAISE EXCEPTION 'Active database administrator directly read another member''s private Daily reflections.';
  END IF;

  v_denied := false;
  BEGIN
    INSERT INTO public.daily_reflections (
      user_id, daily_post_id, reflection_text, is_private
    )
    VALUES (
      '00000000-0000-4000-8000-000000000101',
      (SELECT id FROM public.daily_posts WHERE slug = 'c300-privacy-test-owner-write-daily-post'),
      'C302_ADMIN_CROSS_MEMBER_REFLECTION_INSERT_SHOULD_FAIL',
      true
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Active database administrator inserted a Daily reflection for another member.';
  END IF;

  UPDATE public.daily_reflections
  SET reflection_text = 'C302_ADMIN_CROSS_MEMBER_REFLECTION_UPDATE_SHOULD_FAIL'
  WHERE user_id = '00000000-0000-4000-8000-000000000101'
    AND reflection_text = 'C300_PRIVATE_DAILY_REFLECTION_OWNER_UPDATE_SENTINEL';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'Active database administrator updated another member''s Daily reflection.';
  END IF;

  DELETE FROM public.daily_reflections
  WHERE user_id = '00000000-0000-4000-8000-000000000101'
    AND reflection_text = 'C300_PRIVATE_DAILY_REFLECTION_OWNER_UPDATE_SENTINEL';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'Active database administrator deleted another member''s Daily reflection.';
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

ROLLBACK;

\echo 'Privacy and authorization database behavior assertions PASS'
