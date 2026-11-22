\set ON_ERROR_STOP on

-- The historical policy fixture is committed only long enough to cross the
-- migration-023 boundary; remove its synthetic rows before cleanup assertions.
DELETE FROM public.offerings
WHERE id IN (
  '00000000-0000-4000-8000-000000000210',
  '00000000-0000-4000-8000-000000000211'
);

DELETE FROM auth.users
WHERE id IN (
  '00000000-0000-4000-8000-000000000110',
  '00000000-0000-4000-8000-000000000111'
);
