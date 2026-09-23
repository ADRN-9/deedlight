import fs from "node:fs";

const files = {
  migration: "supabase/migrations/202609230019_sprint12_2_gentle_delivery_foundation.sql",
  reminderAction: "app/settings/reminders/actions.ts",
  packageJson: "package.json",
  wrangler: "wrangler.jsonc",
  sprintDoc: "docs/SPRINT_12_2_GENTLE_DELIVERY_FOUNDATION.md",
};

function read(path) {
  if (!fs.existsSync(path)) {
    throw new Error(`Required Sprint 12.2 file is missing: ${path}`);
  }
  return fs.readFileSync(path, "utf8");
}

function requireMatch(name, text, pattern) {
  if (!pattern.test(text)) {
    throw new Error(`Sprint 12.2 security assertion failed: ${name}`);
  }
  console.log(`PASS: ${name}`);
}

function requireAbsent(name, text, pattern) {
  if (pattern.test(text)) {
    throw new Error(`Sprint 12.2 security assertion failed: ${name}`);
  }
  console.log(`PASS: ${name}`);
}

const migration = read(files.migration);
const reminderAction = read(files.reminderAction);
const packageJson = read(files.packageJson);
const wrangler = read(files.wrangler);
const sprintDoc = read(files.sprintDoc);

requireMatch(
  "Reminder writes use a validating SECURITY DEFINER RPC",
  migration,
  /create or replace function public\.set_daily_reminder_preference\([\s\S]*?security definer[\s\S]*?pg_catalog\.pg_timezone_names/i,
);

requireMatch(
  "Authenticated direct reminder INSERT and UPDATE privileges are revoked",
  migration,
  /revoke insert, update[\s\S]*?on table public\.daily_reminder_preferences[\s\S]*?from authenticated;/i,
);

requireMatch(
  "Reminder server action uses the validating RPC",
  reminderAction,
  /\.rpc\(\s*"set_daily_reminder_preference"/m,
);

requireAbsent(
  "Reminder server action no longer directly upserts preference rows",
  reminderAction,
  /\.from\("daily_reminder_preferences"\)[\s\S]*?\.upsert\(/m,
);

requireMatch(
  "Delivery ledger has RLS enabled",
  migration,
  /alter table public\.delivery_ledger enable row level security;/i,
);

requireMatch(
  "Browser roles have no delivery ledger privileges",
  migration,
  /revoke all privileges[\s\S]*?on table public\.delivery_ledger[\s\S]*?from public, anon, authenticated;/i,
);

requireMatch(
  "Delivery ledger privileges are service-role only",
  migration,
  /grant all privileges[\s\S]*?on table public\.delivery_ledger[\s\S]*?to service_role;/i,
);

for (const fn of [
  "enqueue_due_daily_reminders",
  "enqueue_weekly_goodness_delivery",
  "claim_delivery_jobs",
  "authorize_delivery_job",
  "mark_delivery_sent",
  "mark_delivery_failed",
]) {
  requireMatch(
    `${fn} is SECURITY DEFINER with a constrained search path`,
    migration,
    new RegExp(
      `create or replace function public\\.${fn}\\([\\s\\S]*?security definer[\\s\\S]*?set search_path = public, auth, pg_temp`,
      "i",
    ),
  );

  requireMatch(
    `${fn} browser execution is revoked before service-role grant`,
    migration,
    new RegExp(
      `revoke all privileges[\\s\\S]*?on function public\\.${fn}\\([\\s\\S]*?from public, anon, authenticated;[\\s\\S]*?grant execute[\\s\\S]*?to service_role;`,
      "i",
    ),
  );
}

requireMatch(
  "Daily enqueue filters for enabled preferences and non-suspended profiles",
  migration,
  /enqueue_due_daily_reminders[\s\S]*?p\.is_suspended = false[\s\S]*?drp\.daily_enabled = true/i,
);

requireMatch(
  "Daily enqueue validates stored timezones through PostgreSQL timezone catalog",
  migration,
  /enqueue_due_daily_reminders[\s\S]*?pg_catalog\.pg_timezone_names/i,
);

requireMatch(
  "Weekly enqueue requires current newsletter consent",
  migration,
  /enqueue_weekly_goodness_delivery[\s\S]*?np\.weekly_enabled = true[\s\S]*?np\.consented_at is not null/i,
);

requireMatch(
  "Weekly enqueue requires an active member and confirmed account email",
  migration,
  /enqueue_weekly_goodness_delivery[\s\S]*?p\.is_suspended = false[\s\S]*?u\.email_confirmed_at is not null/i,
);

requireMatch(
  "Queue deduplication is enforced by a unique key",
  migration,
  /unique \(kind, user_id, delivery_key\)/i,
);

requireMatch(
  "Pre-transport authorization cancels stale jobs",
  migration,
  /authorize_delivery_job[\s\S]*?state = 'cancelled'[\s\S]*?authorization_revoked/i,
);

const ledgerBlock = migration.match(
  /create table if not exists public\.delivery_ledger \([\s\S]*?\n\);/i,
)?.[0] ?? "";

requireAbsent(
  "Delivery ledger does not store recipient email addresses",
  ledgerBlock,
  /\bemail\b/i,
);

requireAbsent(
  "Delivery ledger does not store reflection or Offering content",
  ledgerBlock,
  /reflection|offering|body|saved_light/i,
);

requireAbsent(
  "No outbound email/SMS provider dependency is introduced",
  packageJson,
  /"(?:resend|@sendgrid\/mail|postmark|mailgun|twilio|web-push)"\s*:/i,
);

requireAbsent(
  "Cloudflare Cron Triggers remain unconfigured",
  wrangler,
  /"triggers"\s*:|"crons"\s*:/i,
);

requireMatch(
  "Sprint documentation explicitly keeps outbound delivery inactive",
  sprintDoc,
  /will \*\*not\*\* add or imply active delivery/i,
);

console.log("Sprint 12.2 delivery security assertions: PASS");
