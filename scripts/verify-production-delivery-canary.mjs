import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const canary = readFileSync("lib/delivery/production-canary.ts", "utf8");
const worker = readFileSync("custom-worker.ts", "utf8");

const requiredCanaryFragments = [
  'PRODUCTION_DELIVERY_CANARY_PATH = "/__ops/delivery-canary"',
  'APPROVED_CANARY_EMAIL = "admin@deedlight.com"',
  'CANARY_JOB_HEADER = "x-deedlight-canary-job"',
  'env.DELIVERY_ENABLED !== "false"',
  'DELIVERY_ENABLED: "true"',
  'DELIVERY_BATCH_SIZE: "1"',
  'claimable.length !== 1',
  'claimable[0].id !== requestedJobId',
  'claimable[0].kind !== "daily_reminder"',
  'claimable[0].transport_started_at !== null',
  'recipientEmail !== APPROVED_CANARY_EMAIL',
  'preference?.daily_enabled !== true',
  'profile?.is_suspended === true',
  'runtime.claim(now, 1)',
  'claimed[0].jobId !== requestedJobId',
  'processClaimedDelivery({',
  'evidence?.state !== "sent"',
  'https://api.resend.com/emails/${encodeURIComponent(evidence.provider_result_id)}',
  'providerEvidence: providerResponse.ok',
];

for (const fragment of requiredCanaryFragments) {
  assert.ok(canary.includes(fragment), `Missing canary safety fragment: ${fragment}`);
}

assert.ok(
  worker.includes('handleProductionDeliveryCanary(request, env)'),
  "Worker must invoke the canary gate before normal fetch handling.",
);
assert.ok(
  worker.indexOf("handleProductionDeliveryCanary(request, env)") <
    worker.indexOf("handler.fetch(request, env, ctx)"),
  "Canary interception must happen before the normal OpenNext fetch handler.",
);

assert.ok(
  !canary.includes("enqueueDaily") && !canary.includes("enqueueWeekly"),
  "The canary endpoint must never enqueue a population-wide delivery batch.",
);
assert.ok(
  !canary.includes("runScheduledDelivery"),
  "The canary endpoint must not invoke the global scheduler.",
);

console.log("Production delivery canary safety assertions passed.");
