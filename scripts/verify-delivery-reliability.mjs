import fs from "node:fs";

const files = {
  migration: "supabase/migrations/202609230020_delivery_reliability_hardening.sql",
  aggregateSql: "supabase/run_in_sql_editor_all.sql",
  packageJson: "package.json",
  wrangler: "wrangler.jsonc",
  sprintDoc: "docs/DELIVERY_RELIABILITY_HARDENING.md",
};

function read(path) {
  if (!fs.existsSync(path)) {
    throw new Error(`Required delivery reliability file is missing: ${path}`);
  }
  return fs.readFileSync(path, "utf8");
}

function requireMatch(name, text, pattern) {
  if (!pattern.test(text)) {
    throw new Error(`Delivery reliability security assertion failed: ${name}`);
  }
  console.log(`PASS: ${name}`);
}

function requireAbsent(name, text, pattern) {
  if (pattern.test(text)) {
    throw new Error(`Delivery reliability security assertion failed: ${name}`);
  }
  console.log(`PASS: ${name}`);
}

const migration = read(files.migration);
const aggregateSql = read(files.aggregateSql);
const packageJson = read(files.packageJson);
const wrangler = read(files.wrangler);
const sprintDoc = read(files.sprintDoc);

for (const column of [
  "claim_expires_at",
  "attempt_count",
  "last_attempt_at",
  "next_attempt_at",
]) {
  requireMatch(
    `Delivery ledger adds ${column}`,
    migration,
    new RegExp(`add column ${column}\\b`, "i"),
  );
}

requireMatch(
  "Migration refuses live claimed jobs",
  migration,
  /where state = 'claimed'[\s\S]*?raise exception 'Delivery reliability hardening refuses to migrate live claimed jobs\.'/i,
);

requireMatch(
  "Attempt count is bounded",
  migration,
  /delivery_ledger_attempt_count_check[\s\S]*?attempt_count between 0 and 5/i,
);

requireMatch(
  "Claim state requires a token and finite lease",
  migration,
  /delivery_ledger_claim_lease_check[\s\S]*?state = 'claimed'[\s\S]*?claim_token is not null[\s\S]*?claim_expires_at is not null/i,
);

requireMatch(
  "Claim RPC reclaims expired leases",
  migration,
  /claim_delivery_jobs[\s\S]*?dl\.state = 'claimed'[\s\S]*?dl\.claim_expires_at <= p_now[\s\S]*?dl\.attempt_count < 5/i,
);

requireMatch(
  "Each claim gets a five minute lease and increments attempts",
  migration,
  /claim_expires_at = p_now \+ interval '5 minutes'[\s\S]*?attempt_count = dl\.attempt_count \+ 1/i,
);

requireMatch(
  "Expired fifth attempts become terminal retry exhaustion",
  migration,
  /claim_delivery_jobs[\s\S]*?attempt_count >= 5[\s\S]*?error_code = 'retry_exhausted'/i,
);

for (const fn of [
  "claim_delivery_jobs",
  "authorize_delivery_job",
  "retry_delivery_job",
  "mark_delivery_sent",
  "mark_delivery_failed",
]) {
  requireMatch(
    `${fn} is SECURITY DEFINER with constrained search path`,
    migration,
    new RegExp(
      `create or replace function public\\.${fn}\\([\\s\\S]*?security definer[\\s\\S]*?set search_path = public, auth, pg_temp`,
      "i",
    ),
  );

  requireMatch(
    `${fn} remains service-role only`,
    migration,
    new RegExp(
      `revoke all privileges[\\s\\S]*?on function public\\.${fn}\\([\\s\\S]*?from public, anon, authenticated;[\\s\\S]*?grant execute[\\s\\S]*?to service_role;`,
      "i",
    ),
  );
}

requireMatch(
  "Authorization requires a live lease",
  migration,
  /authorize_delivery_job[\s\S]*?claim_expires_at is null[\s\S]*?claim_expires_at <= now\(\)/i,
);

requireMatch(
  "Retry time is bounded to 24 hours",
  migration,
  /retry_delivery_job[\s\S]*?p_retry_at <= now\(\)[\s\S]*?p_retry_at > now\(\) \+ interval '24 hours'/i,
);

requireMatch(
  "Temporary retry uses next_attempt_at",
  migration,
  /retry_delivery_job[\s\S]*?state = 'queued'[\s\S]*?next_attempt_at = p_retry_at/i,
);

const retryFunction = migration.match(
  /create or replace function public\.retry_delivery_job\([\s\S]*?\n\$\$;/i,
)?.[0] ?? "";

requireAbsent(
  "Retry does not rewrite semantic scheduled_for",
  retryFunction,
  /scheduled_for\s*=/i,
);

for (const fn of ["mark_delivery_sent", "mark_delivery_failed"]) {
  requireMatch(
    `${fn} requires an unexpired lease`,
    migration,
    new RegExp(
      `${fn}[\\s\\S]*?claim_expires_at is not null[\\s\\S]*?claim_expires_at > now\\(\\)`,
      "i",
    ),
  );
}

requireAbsent(
  "Reliability migration does not add recipient email storage",
  migration,
  /add column\s+(?:recipient_)?email\b/i,
);

requireAbsent(
  "No outbound provider dependency is introduced",
  packageJson,
  /"(?:resend|@sendgrid\/mail|postmark|mailgun|twilio|web-push)"\s*:/i,
);

requireAbsent(
  "Cloudflare Cron Triggers remain unconfigured",
  wrangler,
  /"triggers"\s*:|"crons"\s*:/i,
);

requireMatch(
  "Reliability documentation keeps outbound delivery inactive",
  sprintDoc,
  /does \*\*not\*\* add:[\s\S]*?email\/SMS\/push provider[\s\S]*?Cloudflare Cron Trigger/i,
);

if (!aggregateSql.includes(migration.trim())) {
  throw new Error(
    "Delivery reliability security assertion failed: canonical migration is not mirrored verbatim in supabase/run_in_sql_editor_all.sql",
  );
}
console.log("PASS: canonical migration is mirrored verbatim in aggregate SQL");

console.log("Delivery reliability security assertions: PASS");
