# Deedlight Sprint 5 — Admin Content Quality + Moderation Upgrade

This patch adds the moderation and content-quality layer needed after reactions:

- Admin edit-before-approval and edit-after-approval
- Admin typo/content correction for title, body, takeaway, media URL, type, anonymity, and reflections
- Admin hide/reject/request-edit actions with notes
- Public report form on Offering detail pages
- Reports queue at `/admin/reports`
- Reported Offerings are lifted in `/admin/offerings`
- Admin can resolve or dismiss reports from the Offering review page
- `/debug/auth` becomes admin-only
- Improved admin dashboard links

## Files to add/replace

```text
app/admin/page.tsx
app/admin/offerings/page.tsx
app/admin/offerings/[id]/page.tsx
app/admin/offerings/[id]/actions.ts
app/admin/reports/page.tsx
app/debug/auth/page.tsx
app/offerings/[id]/page.tsx
components/offerings/report-offering-form.tsx
lib/data/offerings.ts
lib/types.ts
supabase/migrations/202607260005_sprint5_moderation.sql
```

## Apply

Copy the files into your existing Deedlight repo, then run:

```bash
git add app/admin/page.tsx app/admin/offerings/page.tsx app/admin/offerings/[id]/page.tsx app/admin/offerings/[id]/actions.ts app/admin/reports/page.tsx app/debug/auth/page.tsx app/offerings/[id]/page.tsx components/offerings/report-offering-form.tsx lib/data/offerings.ts lib/types.ts supabase/migrations/202607260005_sprint5_moderation.sql
git commit -m "Implement Sprint 5 moderation and content quality"
git push
```

Then apply the Supabase migration:

```bash
npx supabase db push
```

Or paste and run this file in Supabase SQL Editor:

```text
supabase/migrations/202607260005_sprint5_moderation.sql
```

## Test checklist

1. Open `/admin/offerings` as admin.
2. Open an approved Offering in admin review.
3. Correct a typo in the title and click **Save content edits**.
4. Open the public Offering and confirm the corrected title appears.
5. Open an Offering detail page as a signed-in normal user and submit a report.
6. Open `/admin/reports` and confirm the report appears.
7. Open the reported Offering in admin, hide it, and confirm it disappears from `/offerings`.
8. Test resolving or dismissing the report.
9. Open `/debug/auth` while logged out or as a non-admin and confirm it is not public anymore.

## Notes

- Reports are private to admins and the reporting user.
- Anonymous Offerings still hide the author publicly, but admins can see the internal user id.
- This patch does not yet add full user notifications for request-edit messages; that can be Sprint 6 or 7.
