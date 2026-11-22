\set ON_ERROR_STOP on

-- Exact historical Sprint 5 policy, reintroduced as a disposable regression
-- fixture so migration 023 must remove a real broad-read policy.
DROP POLICY IF EXISTS "offerings_select_public_or_own" ON public.offerings;
CREATE POLICY "offerings_select_public_or_own"
ON public.offerings
FOR SELECT
USING (
  status = 'approved'
  OR user_id = auth.uid()
  OR public.is_admin()
);

BEGIN;

INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES
  ('00000000-0000-4000-8000-000000000110', 'legacy-policy-owner@privacy-test.invalid', '{"display_name":"Legacy Policy Owner"}'::jsonb),
  ('00000000-0000-4000-8000-000000000111', 'legacy-policy-reader@privacy-test.invalid', '{"display_name":"Legacy Policy Reader"}'::jsonb);

INSERT INTO public.offerings (
  id, user_id, offering_type, title, body, is_anonymous, status, published_at
)
VALUES
  ('00000000-0000-4000-8000-000000000210', '00000000-0000-4000-8000-000000000110', 'good_deed', 'Legacy policy owner Offering', 'Synthetic owner Offering used only to prove the historical broad-read policy.', false, 'approved', now()),
  ('00000000-0000-4000-8000-000000000211', '00000000-0000-4000-8000-000000000111', 'good_deed', 'Legacy policy cross-member Offering', 'Synthetic other-member Offering used only to prove the historical broad-read policy.', false, 'approved', now());

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000110', true);

DO $$
BEGIN
  IF current_user <> 'authenticated'
     OR auth.uid() <> '00000000-0000-4000-8000-000000000110'::uuid THEN
    RAISE EXCEPTION 'Legacy policy fixture is not running as its synthetic reader.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.offerings
    WHERE id = '00000000-0000-4000-8000-000000000211'
      AND user_id = '00000000-0000-4000-8000-000000000111'
  ) THEN
    RAISE EXCEPTION 'Historical Sprint 5 policy did not reproduce cross-member approved Offering access.';
  END IF;
END
$$;

RESET ROLE;
ROLLBACK;

\echo 'Historical Sprint 5 broad Offering policy fixture: PASS'
