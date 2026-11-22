\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES (
  '00000000-0000-4000-8000-000000000109',
  'forced-failure@privacy-test.invalid',
  '{"display_name":"Forced Failure Fixture"}'::jsonb
);

DO $$
BEGIN
  RAISE EXCEPTION 'C296 intentional cleanup probe failure';
END
$$;

COMMIT;
