import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const root = process.cwd();
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");
const fail = (message) => {
  console.error(`Gentle delivery transport assertion failed: ${message}`);
  process.exit(1);
};
const expect = (condition, message) => {
  if (!condition) fail(message);
};

const migration = read("supabase/migrations/202609230021_gentle_delivery_transport.sql");
const aggregate = read("supabase/run_in_sql_editor_all.sql");
const config = read("lib/delivery/config.ts");
const resend = read("lib/delivery/resend-transport.ts");
const runner = read("lib/delivery/run-delivery.ts");
const scheduler = read("lib/delivery/scheduler.ts");
const runtime = read("lib/delivery/supabase-runtime.ts");
const message = read("lib/delivery/message.ts");
const worker = read("custom-worker.ts");
const wrangler = read("wrangler.jsonc");

expect(
  aggregate.includes(migration.trim()),
  "migration 021 must be mirrored verbatim in run_in_sql_editor_all.sql",
);

for (const fn of ["begin_delivery_transport", "enqueue_current_weekly_goodness_if_curated"]) {
  expect(migration.includes(`function public.${fn}`), `${fn} is missing`);
}
expect((migration.match(/security definer/g) ?? []).length >= 2, "transport RPCs must be security definer");
expect((migration.match(/set search_path = public, auth, pg_temp/g) ?? []).length >= 2, "transport RPCs need constrained search_path");
expect(migration.includes("from public, anon, authenticated"), "browser RPC privileges must be revoked");
expect((migration.match(/to service_role/g) ?? []).length >= 2, "transport RPCs must be service-role only");

expect(config.includes('env.DELIVERY_ENABLED !== "true"'), "delivery kill switch must fail closed");
expect(config.includes('provider !== "resend"'), "unsupported providers must fail closed");
expect(config.includes('requireValue(env, "SUPABASE_SERVICE_ROLE_KEY")'), "service-role key must be mandatory when enabled");
expect(!config.includes("NEXT_PUBLIC_SUPABASE_ANON_KEY"), "delivery config must not use the browser anon key");
expect(!config.includes("normalizeSupabaseUrl"), "delivery config must not use browser URL recovery/fallback");

expect(resend.includes('"Idempotency-Key"'), "provider request must carry an idempotency key");
expect(resend.includes("https://api.resend.com/emails"), "provider endpoint must be explicit");
expect(resend.includes("AbortSignal.timeout"), "provider call must have a bounded timeout");
expect(resend.includes("provider_ambiguous_response"), "ambiguous success must fail safely");
expect(runner.includes("provider_idempotency_window_expired"), "provider idempotency horizon must be enforced");
expect((runner.match(/gateway\.authorize\(job\)/g) ?? []).length >= 2, "authorization must be checked again immediately before transport");
expect(runtime.includes("auth.admin.getUserById"), "recipient must be resolved from Supabase Auth at send time");
expect(!runtime.includes("NEXT_PUBLIC_SUPABASE_URL"), "service-role runtime must not use public Supabase config");

expect(!message.match(/reflection|saved light|journey content|offering body/i), "transport template must not include private member content");
expect(message.includes("/settings/reminders"), "daily message needs an opt-out settings path");
expect(message.includes("/settings/newsletter"), "weekly message needs an opt-out settings path");

const preservesGeneratedFetch =
  worker.includes("fetch: handler.fetch") ||
  worker.includes("handler.fetch(request, env, ctx)");
expect(preservesGeneratedFetch, "custom worker must preserve delegation to the generated Next fetch handler");
expect(worker.includes("async scheduled"), "custom worker must expose the scheduled delivery event");
expect(!worker.includes("/api/"), "scheduler must not add a browser-accessible service-role route");
expect(scheduler.includes("DAILY_DELIVERY_CRON"), "daily scheduler path is missing");
expect(scheduler.includes("WEEKLY_DELIVERY_CRON"), "weekly scheduler path is missing");

const wranglerConfig = JSON.parse(wrangler);
expect(wranglerConfig.main === "./custom-worker.ts", "Wrangler must use the custom worker entrypoint");
expect(Array.isArray(wranglerConfig.triggers?.crons), "Wrangler cron configuration must be explicit");
expect(wranglerConfig.triggers.crons.length === 0, "Production cron triggers must remain disabled before rollout");

console.log("Gentle delivery transport security assertions: PASS");
