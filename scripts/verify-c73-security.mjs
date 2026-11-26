import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const read=(name)=>readFileSync(name,"utf8");
const sql=read("supabase/migrations/202611130030_global_provider_security_cutover.sql");
const runtime=read("lib/delivery/supabase-runtime.ts");
const scheduler=read("lib/delivery/scheduler.ts");
const route=read("app/api/webhooks/resend/route.ts");
const verifier=read("lib/delivery/resend-webhook.ts");
const destination=read("lib/supabase/trusted-destination.ts");
const projectIdentity=read("lib/supabase/project-identity.ts");
for(const p of [
"supabase/migrations/202611130025_delivery_kind_claim_isolation.sql",
"supabase/migrations/202611130026_resend_webhook_lifecycle.sql",
"supabase/migrations/202611130027_recipient_suppression_serialization.sql",
"supabase/migrations/202611130028_database_authoritative_recipient_binding.sql",
"supabase/migrations/202611130029_global_provider_event_registry.sql",
]) assert(read(p).includes("BEGIN;") || read(p).includes("begin;"));
assert(runtime.includes('p_kind: kind'));
assert(runtime.includes('begin_delivery_transport_identity_bound'));
assert(runtime.includes('mark_delivery_sent_identity_bound'));
assert(!runtime.includes('this.client.rpc("mark_delivery_sent"'));
assert(!runtime.includes('this.client.rpc("begin_delivery_transport"'));
assert(scheduler.includes('"daily_reminder"') && scheduler.includes('"weekly_newsletter"'));
assert(sql.includes("ENABLE ALWAYS TRIGGER c73_registry_guard"));
assert(sql.includes("ENABLE ALWAYS TRIGGER c73_transport_safety"));
assert(sql.includes("global event identity") || sql.includes("Global event identity"));
assert(sql.includes("provider_suppressed=true"));
assert(sql.includes("Legacy webhook identity entry point disabled"));
assert(sql.includes("deedlight_record_resend_verified"));
assert(route.includes('readLimitedRawBody(request)'));
assert(route.includes('isTrustedSupabaseDestination(supabaseUrl)'));
assert(route.includes('@/lib/supabase/trusted-destination'));
assert(projectIdentity.includes('DEEDLIGHT_SUPABASE_PROJECT_REF = "xaipiovflxomcbfwtwmu"'));
assert(destination.includes('value === DEEDLIGHT_SUPABASE_ORIGIN'));
assert(destination.includes('url.protocol === "https:"'));
assert(destination.includes('url.port === ""'));
assert(destination.includes('url.username === ""'));
assert(destination.includes('url.pathname === "/"'));
assert(destination.includes('url.search === ""'));
assert(destination.includes('url.hash === ""'));
assert(route.indexOf('!isTrustedSupabaseDestination(supabaseUrl)') < route.indexOf('createClient(supabaseUrl, serviceRoleKey'));
assert(route.includes('status: 503'));
assert(route.includes('deedlight_record_resend_delivery_v2'));
assert(route.includes('deedlight_record_resend_suppression_verified'));
assert(!route.includes("NEXT_PUBLIC_"));
assert(verifier.includes('new Webhook(secret).verify(rawBody'));
assert(verifier.includes('svix-timestamp'));
assert(verifier.includes('MAX_TIMESTAMP_SKEW_SECONDS'));
console.log("C73 provider event, webhook and kind-isolation security assertions: PASS");
