# Deedlight Sprint 4 — Reactions + Rising Goodness

This patch implements the Sprint 4 social engine:

- Bless reaction
- Inspired reaction
- Did too reaction
- Duplicate reaction prevention through the existing unique constraint
- Optimistic client UI for faster feedback
- Reaction count triggers and count repair SQL
- Safer RLS for reactions
- Real `/rising` ranking using a new `offerings_rising` view
- Reaction buttons on Offering cards and Offering detail pages

## Files to add/replace

```text
components/offerings/reaction-buttons.tsx
components/offerings/offering-card.tsx
app/offerings/[id]/page.tsx
app/rising/page.tsx
lib/data/offerings.ts
lib/types.ts
supabase/migrations/202607260004_sprint4_reactions.sql
```

## Apply

Copy the files into your existing Deedlight repo, then run:

```bash
git add components/offerings/reaction-buttons.tsx components/offerings/offering-card.tsx app/offerings/[id]/page.tsx app/rising/page.tsx lib/data/offerings.ts lib/types.ts supabase/migrations/202607260004_sprint4_reactions.sql
git commit -m "Implement Sprint 4 reactions and rising ranking"
git push
```

Then apply the Supabase migration:

```bash
npx supabase db push
```

Or paste this file into Supabase SQL Editor and run it:

```text
supabase/migrations/202607260004_sprint4_reactions.sql
```

## Test checklist

1. Open `/offerings` while logged out.
2. Click Bless/Inspired/Did too on an approved Offering.
   - Expected: a sign-in message appears.
3. Sign in.
4. Click Bless.
   - Expected: button becomes active and count increases by 1.
5. Click Bless again.
   - Expected: button becomes inactive and count decreases by 1.
6. Click Inspired and Did too.
   - Expected: both can be active together.
7. Refresh the page.
   - Expected: your active reactions remain active.
8. Open `/offerings/[id]`.
   - Expected: detail page shows the same counts and active reaction state.
9. Open `/rising`.
   - Expected: approved Offerings are ranked by reaction score.
10. Check Supabase:

```sql
select
  o.title,
  o.bless_count,
  o.inspired_count,
  o.carried_forward_count,
  o.bless_score
from public.offerings o
where o.status = 'approved'
order by o.bless_score desc;
```

## Important notes

- Users can choose multiple reactions on the same Offering: Bless, Inspired, and Did too are separate signals.
- The unique constraint prevents duplicate reactions of the same type by the same user.
- The public only sees aggregate counts, not individual reaction rows.
- Logged-in users can read only their own reaction rows so the UI can show active/inactive state.
