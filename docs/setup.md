# Deedlight Sprint 1 Setup

## 1. Install dependencies

```bash
npm install
```

## 2. Create Supabase project

Create a Supabase project, then copy:

- Project URL
- anon public key
- service role key, server only

Create `.env.local` from `.env.local.example`.

```bash
cp .env.local.example .env.local
```

Create `.dev.vars` from `.dev.vars.example` for Cloudflare preview.

```bash
cp .dev.vars.example .dev.vars
```

## 3. Run database migrations locally

Install Supabase CLI 3.2.0 using the official Supabase CLI installation instructions and verify `supabase --version` reports `3.2.0`. Start the local stack and apply migrations locally:

```bash
supabase start
npm run supabase:push
```

To discard local database changes and rebuild from local migrations:

```bash
npm run supabase:reset
```

Both generic npm commands are local-only wrappers. `supabase:reset` rejects all forwarded arguments, including `--remote` and `--yes`.

For an explicitly approved non-Production hosted project, follow [Supabase CLI target security](./SUPABASE_CLI_TARGET_SECURITY.md). The repository allowlist is intentionally empty until the project owner supplies authoritative non-Production project references. Remote migration commands therefore fail closed in the current configuration.

## 4. Run locally

```bash
npm run dev
```

Open the local app.

## 5. Make yourself admin

After signing up, run this in Supabase SQL editor, replacing the email:

```sql
update public.profiles
set role = 'admin'
where user_id = (
  select id from auth.users where email = 'your@email.com'
);
```

## 6. Connect GitHub

```bash
git init
git add .
git commit -m "Initial Deedlight Sprint 1 foundation"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/deedlight.git
git push -u origin main
```

## 7. Deploy to Cloudflare Workers

Login and deploy:

```bash
npx wrangler login
npm run deploy
```

Set these Cloudflare environment variables in the Cloudflare dashboard or with Wrangler secrets where appropriate:

- NEXT_PUBLIC_SITE_URL=https://deedlight.com
- NEXT_PUBLIC_SUPABASE_URL
- NEXT_PUBLIC_SUPABASE_ANON_KEY

Use Wrangler secrets for private values:

```bash
npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY
```

## 8. Connect deedlight.com

In Cloudflare Workers dashboard, connect the deployed Worker to the custom domain `deedlight.com`. Also add `www.deedlight.com` if you want it.

## Production migration warning

Do not use `.github/workflows/supabase-migrations.yml`. It is a legacy manually dispatchable workflow and is not an approved Production authorization boundary. It remains in the current `main` tree pending the separate emergency-removal change. This remediation does not restore, dispatch, or modify that workflow.

Production migrations remain blocked until the historical Supabase migration-management discrepancy is reconciled and the required GitHub Environment, credential-scope, and approval protections are independently verified.
