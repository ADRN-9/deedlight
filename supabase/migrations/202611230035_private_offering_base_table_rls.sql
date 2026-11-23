-- DeedLight privacy hardening: public Offering access stays on the projection.
-- The Sprint 5 base-table policy survived Sprint 9's projection boundary and
-- exposed approved rows (including internal columns) to every authenticated member.
-- Preserve the existing owner/admin policies and grants; remove only that stale
-- public-read policy so base-table reads remain owner/admin scoped.

begin;

drop policy if exists "offerings_select_public_or_own"
on public.offerings;

drop policy if exists "offerings_public_approved_read"
on public.offerings;

commit;
