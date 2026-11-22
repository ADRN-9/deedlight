# Cloudflare Worker runtime smoke

This CI-only smoke executes the generated OpenNext Worker under local Wrangler/Workerd. It is not a Production deployment or a substitute for Production smoke evidence.

## Production configuration remains authoritative

The workflow first builds and inspects artifacts using the repository's committed `next.config.ts` and `wrangler.jsonc`. The committed Wrangler configuration retains:

- `global_fetch_strictly_public`
- The production `IMAGES` binding
- An empty Cron schedule

The runtime smoke then creates a temporary `wrangler.runtime-smoke.jsonc` from the committed configuration. It removes only `global_fetch_strictly_public` for the local test Worker because the fixture Supabase hostname resolves to loopback. The temporary config retains the Images binding and the empty Cron schedule. It is deleted in the test cleanup path.

The smoke leaves `next.config.ts` unchanged and exercises the production HTTPS wildcard with a public image asset hosted in Supabase's own public Storage project. The local `auth.supabase.co:54321` mock is used only for Auth and REST session/profile calls; it is not used as an image origin.

## Local-only runtime and credentials

- Wrangler runs with `--local`; no Cloudflare account credentials or deployment API are used.
- The smoke starts a local HTTP mock for the Supabase Auth, REST, and Storage endpoints.
- The access token, refresh token, user, profile, and image are synthetic test fixtures.
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` is a non-secret CI placeholder.
- `DELIVERY_ENABLED=false`; no provider key is supplied.
- Cron triggers remain empty; the scheduled handler is not invoked.
- The Worker is not uploaded, deployed, or routed to Production.

## Runtime assertions

The generated Worker is asked to serve:

- Public health and public content routes.
- A private profile route without a session, which must redirect to login.
- The same private route with a valid Supabase session cookie, which must render the authenticated profile.
- A cookie-bearing public route, proving that the configured middleware matcher runs.
- Public icons and Next static assets, proving their middleware exclusions.
- A permitted Supabase Storage image through `/_next/image`, and a disallowed host which must be rejected.

The artifact verifier checks the generated Worker, OpenNext server handler, esbuild metafile, static assets, Next NFT traces, and every emitted source-map file. It resolves and validates references whose maps are present, permits unresolved references only in vendored `node_modules` files whose maps are not copied into the Worker package, and fails on unresolved application-owned references. It also fails if a source-map file is exposed through public ASSETS. OpenNext can retain upstream `sourceMappingURL` comments in vendored dependency files even when the corresponding map is not shipped; those omissions are reported rather than mistaken for available maps. The OpenNext regression test separately exercises the pinned adapter's NFT glob, manifest plugin, cache discovery, and path-normalization call sites.

## Limitations

This test proves local Worker/Workerd execution with a mocked Supabase boundary. It does not prove Production Cloudflare bindings, deployed routing, real Supabase authorization, provider delivery, Cron operation, or Production image-provider behavior. Those require separate Production evidence and approval.
