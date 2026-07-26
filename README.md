# Deedlight Sprint 3 Offering Error + Email Branding Hotfix

This patch does two things:

1. Replaces the create Offering flow with a client-side Supabase insert flow.
   - Errors appear inline.
   - User inputs are preserved.
   - The user stays on the correct step.
   - Successful submission redirects to /journey?offering=submitted.

2. Adds Deedlight-branded Supabase Auth email templates under docs/supabase-email-templates.

## Files to replace/add

- lib/supabase/config.ts
- lib/supabase/client.ts
- app/debug/auth/page.tsx
- app/offerings/new/page.tsx
- components/offerings/create-offering-form.tsx
- docs/supabase-email-templates/*

## Apply

```bash
git add lib/supabase/config.ts lib/supabase/client.ts app/debug/auth/page.tsx app/offerings/new/page.tsx components/offerings/create-offering-form.tsx docs/supabase-email-templates
git commit -m "Improve Offering errors and add Deedlight auth email templates"
git push
```

## Test

1. /debug/auth should show normalizedUrl = https://xaipiovflxomcbfwtwmu.supabase.co
2. Sign in.
3. Open /offerings/new.
4. Submit a complete Offering.
5. You should go to /journey?offering=submitted.
6. Confirm the Offering appears in Supabase with status = pending.
7. Admin approves it from /admin/offerings.
8. It appears publicly on /offerings.
