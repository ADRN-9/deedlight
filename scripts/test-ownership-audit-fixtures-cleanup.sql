-- Remove only the uniquely named disposable test identities and their objects.
REVOKE deedlight_fixture_middle, deedlight_fixture_inherited, deedlight_fixture_setonly
  FROM deedlight_fixture_owner;
REVOKE deedlight_fixture_privileged FROM deedlight_fixture_middle;

DROP OWNED BY deedlight_fixture_owner;
DROP OWNED BY deedlight_fixture_middle;
DROP OWNED BY deedlight_fixture_privileged;
DROP OWNED BY deedlight_fixture_inherited;
DROP OWNED BY deedlight_fixture_setonly;
DROP OWNED BY deedlight_fixture_acl_reader;

DROP ROLE deedlight_fixture_owner;
DROP ROLE deedlight_fixture_middle;
DROP ROLE deedlight_fixture_privileged;
DROP ROLE deedlight_fixture_inherited;
DROP ROLE deedlight_fixture_setonly;
DROP ROLE deedlight_fixture_acl_reader;
