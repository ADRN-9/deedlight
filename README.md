# Deedlight Runtime Hotfix

Replace these files in your repository:

- wrangler.jsonc
- components/layout/public-header.tsx
- lib/data/daily-posts.ts
- lib/data/offerings.ts
- lib/supabase/middleware.ts
- app/api/health/route.ts

Then commit and push:

```bash
git add wrangler.jsonc components/layout/public-header.tsx lib/data/daily-posts.ts lib/data/offerings.ts lib/supabase/middleware.ts app/api/health/route.ts
git commit -m "Fix Cloudflare runtime crash and add health check"
git push
```

After deployment, open:

https://deedlight.engsystems-org.workers.dev/api/health

All boolean fields should be true.
