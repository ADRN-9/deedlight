# Deedlight Sprint 3 — Offerings MVP patch

This patch adds the Goodness Offerings MVP:

- multi-step Create Offering flow
- dignity reminder before posting
- optional image/video URL
- pending review submission
- public approved Offerings feed
- public Offering detail page
- admin review queue
- admin approve / reject / request edit / hide actions
- Journey page showing the user's Offering statuses

## Files to copy

Copy the patch folders into your existing Deedlight repo, preserving paths. These files are intended to add/replace:

- `components/offerings/create-offering-form.tsx`
- `lib/auth/admin.ts`
- `lib/data/offerings.ts`
- `lib/types.ts`
- `app/offerings/new/actions.ts`
- `app/offerings/new/page.tsx`
- `app/offerings/page.tsx`
- `app/offerings/[id]/page.tsx`
- `app/admin/offerings/page.tsx`
- `app/admin/offerings/[id]/page.tsx`
- `app/admin/offerings/[id]/actions.ts`
- `app/journey/page.tsx`
- `supabase/migrations/202607220003_sprint3_offerings_review.sql`

If your Sprint 2 Journey page has custom changes you want to keep, merge `app/journey/page.tsx` manually instead of replacing it.

## Apply

```bash
git status
git add .
git commit -m "Checkpoint before Sprint 3 Offerings MVP"

# Copy these patch files into your repo, then:
git add components/offerings/create-offering-form.tsx lib/auth/admin.ts lib/data/offerings.ts lib/types.ts app/offerings app/admin/offerings app/journey/page.tsx supabase/migrations/202607220003_sprint3_offerings_review.sql
git commit -m "Implement Sprint 3 Offerings MVP"
git push
```

## Run Supabase migration

```bash
npx supabase db push
```

Or paste `supabase/migrations/202607220003_sprint3_offerings_review.sql` into Supabase SQL Editor and run it.

## Test checklist

1. Sign in as a normal user.
2. Open `/offerings/new`.
3. Create an Offering and submit it.
4. Confirm it appears in `/journey` as pending.
5. Confirm it does **not** appear in `/offerings` yet.
6. Sign in as admin.
7. Open `/admin/offerings`.
8. Open the pending Offering.
9. Click **Approve and publish**.
10. Confirm it appears on `/offerings` and `/offerings/[id]`.
11. Test Reject / Request edit / Hide on another Offering.

## Sprint 3 acceptance criteria

- logged-in users can create Offerings
- new Offerings start as pending
- pending Offerings are hidden from public feed
- admin can see pending Offerings
- admin can approve, reject, request edit, and hide
- approved Offerings appear publicly
- anonymous Offerings hide the public author name
- non-admin users cannot access admin review pages
