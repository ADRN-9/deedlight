\set ON_ERROR_STOP on
-- C83: synthetic identities against migrated PostgreSQL 16; never Production.
-- Explicit user-role checks (SET ROLE), not superuser-only policy inspection.
SET statement_timeout = '20s';
CREATE SCHEMA c83_test;
CREATE TABLE c83_test.results (
  scenario text PRIMARY KEY,
  passed boolean NOT NULL
);
GRANT USAGE ON SCHEMA c83_test TO anon, authenticated;
GRANT INSERT ON c83_test.results TO anon, authenticated;

CREATE FUNCTION c83_test.check_count(
  p_sql text, p_expected bigint, p_permission_denied_ok boolean DEFAULT false
) RETURNS boolean
LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog, public AS $fn$
DECLARE v_actual bigint;
BEGIN
  EXECUTE p_sql INTO v_actual;
  RETURN v_actual IS NOT DISTINCT FROM p_expected;
EXCEPTION
  WHEN insufficient_privilege THEN RETURN p_permission_denied_ok;
  WHEN OTHERS THEN RETURN false;
END;
$fn$;
CREATE FUNCTION c83_test.record(p_scenario text, p_passed boolean)
RETURNS void
LANGUAGE sql SECURITY INVOKER SET search_path = pg_catalog, public AS $fn$
  INSERT INTO c83_test.results(scenario, passed)
  VALUES (p_scenario, coalesce(p_passed, false));
$fn$;
REVOKE ALL ON FUNCTION c83_test.check_count(text,bigint,boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION c83_test.record(text,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION c83_test.check_count(text,bigint,boolean) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION c83_test.record(text,boolean) TO anon, authenticated;

-- Auth signup triggers depend on Supabase infrastructure absent from the
-- disposable bootstrap. Seed auth rows as fixture-owner, not through signup.
ALTER TABLE auth.users DISABLE TRIGGER USER;
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES
 ('83000000-0000-0000-0000-000000000001','c83-a@example.test',now()),
 ('83000000-0000-0000-0000-000000000002','c83-b@example.test',now()),
 ('83000000-0000-0000-0000-000000000003','c83-admin@example.test',now());
ALTER TABLE auth.users ENABLE TRIGGER USER;

INSERT INTO public.profiles(user_id,username,display_name,role,is_public)
VALUES
 ('83000000-0000-0000-0000-000000000001','c83-alice','C83 Alice','member',false),
 ('83000000-0000-0000-0000-000000000002','c83-bob','C83 Bob','member',true),
 ('83000000-0000-0000-0000-000000000003','c83-admin','C83 Moderator','admin',false);

INSERT INTO public.daily_lights(id,scheduled_date,title,status) VALUES
 ('83010000-0000-0000-0000-000000000001',current_date,'C83 gentle daily action','published');
INSERT INTO public.daily_reflections(user_id,daily_light_id,reflection_text,reflection)
VALUES ('83000000-0000-0000-0000-000000000001',
 '83010000-0000-0000-0000-000000000001',
 'synthetic-private-journey-note','synthetic-private-journey-note');
INSERT INTO public.daily_deed_completions(user_id,daily_light_id)
VALUES ('83000000-0000-0000-0000-000000000001',
 '83010000-0000-0000-0000-000000000001');
INSERT INTO public.saved_lights(user_id,daily_light_id)
VALUES ('83000000-0000-0000-0000-000000000001',
 '83010000-0000-0000-0000-000000000001');
INSERT INTO public.daily_reminder_preferences(user_id,daily_enabled)
VALUES ('83000000-0000-0000-0000-000000000001',true),
       ('83000000-0000-0000-0000-000000000002',false);
INSERT INTO public.newsletter_preferences(user_id,weekly_enabled,consented_at,consent_source)
VALUES ('83000000-0000-0000-0000-000000000001',true,now(),'settings'),
       ('83000000-0000-0000-0000-000000000002',false,null,null);
INSERT INTO public.invitation_links(id,inviter_user_id,code,accepted_count)
VALUES ('83020000-0000-0000-0000-000000000001',
 '83000000-0000-0000-0000-000000000001',repeat('a',36),1);
INSERT INTO public.invitation_acceptances(invitation_id,invited_user_id)
VALUES ('83020000-0000-0000-0000-000000000001',
 '83000000-0000-0000-0000-000000000002');
INSERT INTO public.offerings(id,user_id,offering_type,title,body,status,is_anonymous,published_at)
VALUES
 ('83030000-0000-0000-0000-000000000001',
 '83000000-0000-0000-0000-000000000001','gratitude','C83 quiet kindness',
 'A synthetic anonymous deed with no identifying details.', 'approved',true,now()),
 ('83030000-0000-0000-0000-000000000002',
 '83000000-0000-0000-0000-000000000002','gratitude','C83 visible kindness',
 'A synthetic nonanonymous deed for the public projection.', 'approved',false,now());
INSERT INTO public.weekly_goodness_features(week_start,offering_id)
VALUES (date_trunc('week',timezone('UTC',now()))::date,
 '83030000-0000-0000-0000-000000000001');
INSERT INTO public.member_moderation_events(member_user_id,actor_user_id,action,reason)
VALUES ('83000000-0000-0000-0000-000000000001',
 '83000000-0000-0000-0000-000000000003','restored',
 'Synthetic moderation context only');
INSERT INTO public.reports(offering_id,reported_by,reason,details)
VALUES ('83030000-0000-0000-0000-000000000001',
 '83000000-0000-0000-0000-000000000002','privacy_concern',
 'Synthetic private report details');

-- Catalog: exact grant and RLS controls, including private email schema.
SELECT c83_test.record('catalog_private_tables_rls',
 (SELECT coalesce(bool_and(c.relrowsecurity),false)
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public'
    AND c.relname IN ('daily_reflections','daily_deed_completions',
      'saved_lights','daily_reminder_preferences','newsletter_preferences',
      'invitation_links','invitation_acceptances','member_moderation_events'))
 AND (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind='r' AND c.relname IN
  ('daily_reflections','daily_deed_completions','saved_lights',
   'daily_reminder_preferences','newsletter_preferences','invitation_links',
   'invitation_acceptances','member_moderation_events'))=8);
SELECT c83_test.record('catalog_auth_users_no_browser_select',
 NOT has_table_privilege('anon','auth.users','SELECT') AND
 NOT has_table_privilege('authenticated','auth.users','SELECT'));
SELECT c83_test.record('catalog_moderation_private',
 NOT has_table_privilege('anon','public.member_moderation_events','SELECT')
 AND NOT has_table_privilege('authenticated','public.member_moderation_events','SELECT')
 AND NOT has_table_privilege('anon','public.invitation_acceptances','SELECT')
 AND NOT has_table_privilege('authenticated','public.invitation_acceptances','SELECT'));
SELECT c83_test.record('catalog_public_projection_columns',
 NOT EXISTS (
   SELECT 1 FROM information_schema.columns
   WHERE table_schema='public'
     AND table_name IN ('profiles_public','offerings_public','offerings_rising',
         'daily_deed_completion_counts')
     AND column_name IN ('email','inviter_user_id','invited_user_id','moderation_note',
        'reflection','reflection_text','consent_source','reminder_time','timezone')
 ));

-- Real anon database role, no JWT subject.
SELECT set_config('request.jwt.claim.sub','',false);
SET ROLE anon;
SELECT c83_test.record('anon_private_journey',
 c83_test.check_count('SELECT count(*) FROM public.daily_reflections',0,true));
SELECT c83_test.record('anon_private_completions',
 c83_test.check_count('SELECT count(*) FROM public.daily_deed_completions',0,true));
SELECT c83_test.record('anon_saved_lights',
 c83_test.check_count('SELECT count(*) FROM public.saved_lights',0,true));
SELECT c83_test.record('anon_reminder_preferences',
 c83_test.check_count('SELECT count(*) FROM public.daily_reminder_preferences',0,true));
SELECT c83_test.record('anon_newsletter_consent',
 c83_test.check_count('SELECT count(*) FROM public.newsletter_preferences',0,true));
SELECT c83_test.record('anon_invitation_attribution',
 c83_test.check_count('SELECT count(*) FROM public.invitation_links',0,true)
 AND c83_test.check_count('SELECT count(*) FROM public.invitation_acceptances',0,true));
SELECT c83_test.record('anon_moderation_and_report_details',
 c83_test.check_count('SELECT count(*) FROM public.member_moderation_events',0,true)
 AND c83_test.check_count('SELECT count(*) FROM public.reports',0,true));
SELECT c83_test.record('anon_auth_addresses',
 c83_test.check_count('SELECT count(*) FROM auth.users',0,true));
SELECT c83_test.record('anon_base_offerings',
 c83_test.check_count('SELECT count(*) FROM public.offerings',0,true));
SELECT c83_test.record('anon_profile_opt_in',
 c83_test.check_count('SELECT count(*) FROM public.profiles_public',1));
SELECT c83_test.record('anon_anonymous_offering_projection',
 c83_test.check_count($q$SELECT count(*) FROM public.offerings_public
 WHERE id='83030000-0000-0000-0000-000000000001'
   AND is_anonymous AND user_id IS NULL
   AND author_name IS NULL AND author_username IS NULL$q$,1));
SELECT c83_test.record('anon_rising_anonymity',
 c83_test.check_count($q$SELECT count(*) FROM public.offerings_rising
 WHERE id='83030000-0000-0000-0000-000000000001'
   AND user_id IS NULL AND author_name IS NULL AND author_username IS NULL$q$,1));
SELECT c83_test.record('anon_weekly_anonymity',
 c83_test.check_count($q$SELECT count(*) FROM public.get_weekly_goodness(12)
 WHERE id='83030000-0000-0000-0000-000000000001'
 AND author_name IS NULL AND author_username IS NULL$q$,1)
 AND c83_test.check_count($q$SELECT count(*) FROM public.get_current_weekly_goodness_feature()
 WHERE id='83030000-0000-0000-0000-000000000001'
 AND author_name IS NULL AND author_username IS NULL$q$,1));
SELECT c83_test.record('anon_public_profile_no_private_fields',
 c83_test.check_count($q$SELECT count(*) FROM public.profiles_public
 WHERE username='c83-bob' AND display_name='C83 Bob'$q$,1)
 AND c83_test.check_count($q$SELECT count(*) FROM public.profiles_public
 WHERE username='c83-alice'$q$,0));
SELECT c83_test.record('anon_admin_functions_denied',
 c83_test.check_count($q$SELECT count(*) FROM public.admin_list_members('all')$q$,0,true)
 AND c83_test.check_count($q$SELECT count(*) FROM public.admin_get_member_context(
   '83000000-0000-0000-0000-000000000001')$q$,0,true));
RESET ROLE;

-- Member A: owner access must continue working.
SELECT set_config('request.jwt.claim.sub','83000000-0000-0000-0000-000000000001',false);
SET ROLE authenticated;
SELECT c83_test.record('owner_private_journey_and_completion',
 c83_test.check_count('SELECT count(*) FROM public.daily_reflections',1)
 AND c83_test.check_count('SELECT count(*) FROM public.daily_deed_completions',1));
SELECT c83_test.record('owner_saved_lights',
 c83_test.check_count('SELECT count(*) FROM public.saved_lights',1));
SELECT c83_test.record('owner_preferences_and_consent',
 c83_test.check_count('SELECT count(*) FROM public.daily_reminder_preferences',1)
 AND c83_test.check_count('SELECT count(*) FROM public.newsletter_preferences',1));
SELECT c83_test.record('owner_invitation_and_profile',
 c83_test.check_count('SELECT count(*) FROM public.invitation_links',1)
 AND c83_test.check_count('SELECT count(*) FROM public.profiles',1));
SELECT c83_test.record('owner_base_offerings_only',
 c83_test.check_count('SELECT count(*) FROM public.offerings',1));
SELECT c83_test.record('owner_invitee_attribution_denied',
 c83_test.check_count('SELECT count(*) FROM public.invitation_acceptances',0,true));
RESET ROLE;

-- Member B: cannot read member A's private rows or privileges.
SELECT set_config('request.jwt.claim.sub','83000000-0000-0000-0000-000000000002',false);
SET ROLE authenticated;
SELECT c83_test.record('cross_member_journey_completion',
 c83_test.check_count('SELECT count(*) FROM public.daily_reflections',0)
 AND c83_test.check_count('SELECT count(*) FROM public.daily_deed_completions',0));
SELECT c83_test.record('cross_member_saved_lights',
 c83_test.check_count('SELECT count(*) FROM public.saved_lights',0));
SELECT c83_test.record('cross_member_preferences',
 c83_test.check_count('SELECT count(*) FROM public.daily_reminder_preferences',1)
 AND c83_test.check_count('SELECT count(*) FROM public.newsletter_preferences',1)
 AND c83_test.check_count($q$SELECT count(*) FROM public.daily_reminder_preferences
 WHERE user_id='83000000-0000-0000-0000-000000000001'$q$,0)
 AND c83_test.check_count($q$SELECT count(*) FROM public.newsletter_preferences
 WHERE user_id='83000000-0000-0000-0000-000000000001'$q$,0));
SELECT c83_test.record('cross_member_invitation_and_profile',
 c83_test.check_count('SELECT count(*) FROM public.invitation_links',0)
 AND c83_test.check_count($q$SELECT count(*) FROM public.profiles
 WHERE user_id='83000000-0000-0000-0000-000000000001'$q$,0));
SELECT c83_test.record('cross_member_base_offering_private',
 c83_test.check_count($q$SELECT count(*) FROM public.offerings
 WHERE user_id='83000000-0000-0000-0000-000000000001'$q$,0));
SELECT c83_test.record('member_moderation_and_auth_denied',
 c83_test.check_count('SELECT count(*) FROM public.member_moderation_events',0,true)
 AND c83_test.check_count('SELECT count(*) FROM auth.users',0,true));
SELECT c83_test.record('member_admin_rpc_denied',
 c83_test.check_count($q$SELECT count(*) FROM public.admin_list_members('all')$q$,0,true)
 AND c83_test.check_count($q$SELECT count(*) FROM public.admin_get_member_context(
 '83000000-0000-0000-0000-000000000001')$q$,0,true));
RESET ROLE;

-- Admin authority is limited to moderation, not the member's private Diary.
SELECT set_config('request.jwt.claim.sub','83000000-0000-0000-0000-000000000003',false);
SET ROLE authenticated;
SELECT c83_test.record('admin_moderation_rpc_authorized',
 c83_test.check_count($q$SELECT count(*) FROM public.admin_get_member_context(
 '83000000-0000-0000-0000-000000000001')$q$,1));
SELECT c83_test.record('admin_context_excludes_private_journey',
 c83_test.check_count($q$SELECT count(*) FROM public.admin_get_member_context(
 '83000000-0000-0000-0000-000000000001') v
 WHERE v::text LIKE '%synthetic-private-journey-note%'$q$,0));
SELECT c83_test.record('admin_member_private_journey_denied',
 c83_test.check_count($q$SELECT count(*) FROM public.daily_reflections
 WHERE user_id='83000000-0000-0000-0000-000000000001'$q$,0,true));
RESET ROLE;

-- Emit all scenarios before failing CI; never print synthetic row contents.
SELECT jsonb_build_object('scenario',scenario,
 'status',CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END)
AS c83_privacy_result FROM c83_test.results ORDER BY scenario;
SELECT jsonb_build_object('scenarios',count(*),
 'passed',count(*) FILTER (WHERE passed),
 'failed',count(*) FILTER (WHERE NOT passed),
 'postgres',current_setting('server_version'),
 'delivery_enabled',false)
AS c83_summary FROM c83_test.results;
DO $fail_closed$
BEGIN
  IF (SELECT count(*) FROM c83_test.results) < 30
     OR EXISTS (SELECT 1 FROM c83_test.results WHERE NOT passed) THEN
    RAISE EXCEPTION 'C83 member privacy invariants FAIL; examine per-scenario results';
  END IF;
END $fail_closed$;
