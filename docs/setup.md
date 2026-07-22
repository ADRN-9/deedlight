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

## 3. Push database migrations

Install and log into Supabase CLI if needed.

```bash
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push
```

Optionally seed local development database:

```bash
npx supabase db reset
```

For a remote-only first setup, you can run the content of `supabase/seed.sql` in the Supabase SQL editor after `db push`.

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

## Optional GitHub Actions deployment

This starter includes two optional workflows:

- `.github/workflows/deploy-cloudflare.yml`
- `.github/workflows/supabase-migrations.yml`

Add these GitHub repository secrets before using them:

```text
CLOUDFLARE_API_TOKEN
CLOUDFLARE_ACCOUNT_ID
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY
SUPABASE_ACCESS_TOKEN
SUPABASE_DB_PASSWORD
SUPABASE_PROJECT_REF
```

Run Supabase migrations manually first until you are comfortable. Use the migration workflow only after confirming the schema locally or in staging.
