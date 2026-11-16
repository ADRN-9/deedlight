-- C101: forward-only member privacy correction; do not apply to Production
-- without live schema reconciliation, independently reviewed source and approval.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '45s';

DO $preflight$
DECLARE
  v_offering_select_policies integer;
BEGIN
  IF to_regclass('public.offerings') IS NULL
    OR to_regclass('public.daily_reflections') IS NULL
    OR to_regprocedure('public.is_admin()') IS NULL
    OR to_regprocedure('public.update_own_offering(uuid,text,text,text,text,text,text,boolean,boolean)') IS NULL
    OR to_regprocedure('public.remove_own_offering(uuid)') IS NULL
    OR to_regprocedure('public.admin_list_offerings(text,integer,uuid[])') IS NOT NULL
    OR EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='offerings'
        AND column_name='owner_feedback'
    )
    OR NOT EXISTS (
      SELECT 1 FROM pg_class WHERE oid='public.offerings'::regclass AND relrowsecurity
    )
    OR NOT EXISTS (
      SELECT 1 FROM pg_class WHERE oid='public.daily_reflections'::regclass AND relrowsecurity
    )
  THEN
    RAISE EXCEPTION 'C101 requires the unmodified C79 Offering/Journey schema'
      USING ERRCODE='55000';
  END IF;

  SELECT count(*) INTO v_offering_select_policies
  FROM pg_policies
  WHERE schemaname='public' AND tablename='offerings'
    AND cmd IN ('SELECT','ALL')
    AND policyname IN (
      'offerings_select_public_or_own','offerings_own_read','offerings_admin_all'
    );
  IF v_offering_select_policies <> 3
    OR EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname='public' AND tablename='offerings'
        AND cmd IN ('SELECT','ALL')
        AND policyname NOT IN (
          'offerings_select_public_or_own','offerings_own_read','offerings_admin_all'
        )
    )
    OR NOT EXISTS (
      SELECT 1 FROM pg_policies WHERE schemaname='public'
        AND tablename='offerings' AND policyname='offerings_select_public_or_own'
        AND cmd='SELECT' AND qual LIKE '%approved%'
    )
  THEN
    RAISE EXCEPTION 'C101 refuses unexpected Offering SELECT policy graph'
      USING ERRCODE='55000';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='daily_reflections' AND policyname='daily reflections select own or admin'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='daily_reflections' AND policyname='daily_reflections_select_own_or_admin'
  ) OR EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public'
      AND tablename='daily_reflections'
      AND policyname NOT IN (
        'daily_reflections_select_own_or_admin',
        'daily reflections select own or admin',
        'daily_reflections_insert_own',
        'daily reflections insert own',
        'daily_reflections_update_own',
        'daily reflections update own or admin',
        'daily_reflections_delete_admin'
      )
  )
  THEN
    RAISE EXCEPTION 'C101 refuses unexpected Daily reflection policy graph'
      USING ERRCODE='55000';
  END IF;
END $preflight$;

-- Old approved-row SELECT made anonymous owner UUIDs and internal notes readable
-- through authenticated PostgREST table access. Public views stay available.
DROP POLICY "offerings_select_public_or_own" ON public.offerings;
-- 'offerings_own_read' and 'offerings_admin_all' remain owner/admin-scoped.

-- Do not copy historical moderation notes into a member-readable field:
-- previous notes may contain internal administrative context.
ALTER TABLE public.offerings
  ADD COLUMN owner_feedback text
  CHECK (owner_feedback IS NULL OR char_length(owner_feedback) <= 1000);

-- RLS controls rows; column grants also hide moderator-only data from owners.
-- Owner-facing queries read owner_feedback, never moderation_note.
REVOKE ALL PRIVILEGES ON TABLE public.offerings
  FROM PUBLIC, anon, authenticated;
GRANT SELECT (
  id,user_id,theme_id,offering_type,title,body,takeaway,media_url,
  media_type,is_anonymous,allow_reflections,location_label,status,
  bless_count,inspired_count,carried_forward_count,reflection_count,
  bless_score,published_at,created_at,updated_at,owner_removed_at,owner_feedback
) ON public.offerings TO authenticated;
GRANT INSERT, UPDATE ON public.offerings TO authenticated;

-- Direct browser UPDATE grants must not allow members to forge moderator fields.
-- Existing definer-owned counter/owner RPCs execute in their controlled context.
CREATE FUNCTION public.c101_guard_offering_private_fields()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path=pg_catalog,pg_temp
AS $guard$
BEGIN
  IF current_user IN ('anon','authenticated') AND NOT public.is_admin() THEN
    IF TG_OP='INSERT' THEN
      IF NEW.moderation_note IS NOT NULL OR NEW.owner_feedback IS NOT NULL
        OR NEW.owner_removed_at IS NOT NULL OR NEW.open_report_count <> 0
        OR NEW.bless_count <> 0 OR NEW.inspired_count <> 0
        OR NEW.carried_forward_count <> 0 OR NEW.reflection_count <> 0
      THEN
        RAISE EXCEPTION 'Member cannot create internal moderation fields'
          USING ERRCODE='42501';
      END IF;
    ELSIF TG_OP='UPDATE' THEN
      IF NEW.moderation_note IS DISTINCT FROM OLD.moderation_note
        OR NEW.owner_feedback IS DISTINCT FROM OLD.owner_feedback
        OR NEW.open_report_count IS DISTINCT FROM OLD.open_report_count
        OR NEW.bless_count IS DISTINCT FROM OLD.bless_count
        OR NEW.inspired_count IS DISTINCT FROM OLD.inspired_count
        OR NEW.carried_forward_count IS DISTINCT FROM OLD.carried_forward_count
        OR NEW.reflection_count IS DISTINCT FROM OLD.reflection_count
        OR NEW.owner_removed_at IS DISTINCT FROM OLD.owner_removed_at
      THEN
        RAISE EXCEPTION 'Member cannot change internal moderation fields'
          USING ERRCODE='42501';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION public.c101_guard_offering_private_fields()
  FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER c101_guard_offering_private_fields
  BEFORE INSERT OR UPDATE ON public.offerings
  FOR EACH ROW EXECUTE FUNCTION public.c101_guard_offering_private_fields();

-- Authorized admin read path; return raw rows only after database-backed check.
-- This endpoint does not expose member data when role/JWT is missing or forged.
CREATE FUNCTION public.admin_list_offerings(
  p_status text DEFAULT 'pending',
  p_limit integer DEFAULT 50,
  p_ids uuid[] DEFAULT NULL
)
RETURNS SETOF public.offerings
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $rpc$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Database-backed admin access required'
      USING ERRCODE='42501';
  END IF;
  IF p_status IS NULL
    OR p_status NOT IN (
      'all','draft','pending','approved','rejected','needs_edit','hidden'
    )
    OR p_limit IS NULL OR p_limit < 1 OR p_limit > 250
    OR (p_ids IS NOT NULL AND cardinality(p_ids)>250)
  THEN
    RAISE EXCEPTION 'Invalid moderation query scope'
      USING ERRCODE='22023';
  END IF;
  RETURN QUERY SELECT o.* FROM public.offerings o
  WHERE (p_status='all' OR o.status=p_status)
    AND (p_ids IS NULL OR o.id=ANY(p_ids))
  ORDER BY o.open_report_count DESC,o.created_at DESC,o.id
  LIMIT p_limit;
END $rpc$;
REVOKE ALL ON FUNCTION public.admin_list_offerings(text,integer,uuid[])
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.admin_list_offerings(text,integer,uuid[])
  TO authenticated,service_role;

-- Private Daily reflections belong to their member, not administrators.
-- Drop ALL historical permissive variants, including the old admin DELETE.
DROP POLICY "daily_reflections_select_own_or_admin" ON public.daily_reflections;
DROP POLICY "daily reflections select own or admin" ON public.daily_reflections;
DROP POLICY "daily_reflections_update_own" ON public.daily_reflections;
DROP POLICY "daily reflections update own or admin" ON public.daily_reflections;
DROP POLICY "daily_reflections_delete_admin" ON public.daily_reflections;

CREATE POLICY c101_daily_reflections_owner_select ON public.daily_reflections
  FOR SELECT TO authenticated USING (user_id=auth.uid());
CREATE POLICY c101_daily_reflections_owner_update ON public.daily_reflections
  FOR UPDATE TO authenticated
  USING (user_id=auth.uid()) WITH CHECK (user_id=auth.uid());
CREATE POLICY c101_daily_reflections_owner_delete ON public.daily_reflections
  FOR DELETE TO authenticated USING (user_id=auth.uid());

REVOKE ALL PRIVILEGES ON TABLE public.daily_reflections
  FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON TABLE public.daily_reflections
  TO authenticated;

-- Fail migration if a permissive old graph or wildcard browser grant persists.
DO $postcheck$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='daily_reflections'
      AND cmd IN ('SELECT','UPDATE','DELETE','ALL')
      AND policyname NOT LIKE 'c101_daily_reflections_owner_%'
  ) OR EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='offerings'
      AND cmd IN ('SELECT','ALL')
      AND policyname NOT IN ('offerings_own_read','offerings_admin_all')
  )
  OR has_column_privilege('authenticated','public.offerings','moderation_note','SELECT')
  OR has_column_privilege('authenticated','public.offerings','open_report_count','SELECT')
  OR has_table_privilege('anon','public.offerings','SELECT')
  OR has_function_privilege('anon',
    'public.admin_list_offerings(text,integer,uuid[])','EXECUTE')
  THEN
    RAISE EXCEPTION 'C101 post-migration privacy privilege invariant failed'
      USING ERRCODE='55000';
  END IF;
END $postcheck$;

NOTIFY pgrst, 'reload schema';
COMMIT;
