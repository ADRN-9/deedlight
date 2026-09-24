import { createClient } from "@supabase/supabase-js";

import { parseDeliveryRuntimeConfig } from "./config.ts";
import { createResendTransport } from "./resend-transport.ts";
import { processClaimedDelivery } from "./run-delivery.ts";
import { createSupabaseDeliveryRuntime } from "./supabase-runtime.ts";

export const PRODUCTION_DELIVERY_CANARY_PATH = "/__ops/delivery-canary";

const APPROVED_CANARY_EMAIL = "admin@deedlight.com";
const CANARY_JOB_HEADER = "x-deedlight-canary-job";
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type DeliveryWorkerEnv = Record<string, string | undefined>;

type LedgerRow = {
  id: string;
  user_id: string;
  kind: string;
  state: string;
  scheduled_for: string;
  next_attempt_at: string | null;
  attempt_count: number;
  claim_expires_at: string | null;
  transport_started_at: string | null;
};

function response(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "cache-control": "no-store",
      "content-type": "application/json; charset=utf-8",
    },
  });
}

function parseDate(value: string | null) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

export function isClaimableCanaryRow(row: LedgerRow, now: Date) {
  if (row.attempt_count >= 5) return false;

  if (row.state === "queued") {
    const readyAt = parseDate(row.next_attempt_at) ?? parseDate(row.scheduled_for);
    return Boolean(readyAt && readyAt.getTime() <= now.getTime());
  }

  if (row.state === "claimed") {
    const expiresAt = parseDate(row.claim_expires_at);
    return Boolean(expiresAt && expiresAt.getTime() <= now.getTime());
  }

  return false;
}

export async function handleProductionDeliveryCanary(
  request: Request,
  env: DeliveryWorkerEnv,
): Promise<Response | null> {
  const url = new URL(request.url);
  if (url.pathname !== PRODUCTION_DELIVERY_CANARY_PATH) return null;

  if (request.method !== "POST") {
    return response(405, { ok: false, error: "method_not_allowed" });
  }

  // The canary is deliberately unavailable once global delivery is enabled.
  if (env.DELIVERY_ENABLED !== "false") {
    return response(409, { ok: false, error: "global_delivery_not_disabled" });
  }

  const requestedJobId = request.headers.get(CANARY_JOB_HEADER)?.trim() ?? "";
  if (!UUID_PATTERN.test(requestedJobId)) {
    return response(404, { ok: false, error: "canary_not_found" });
  }

  // Reuse the exact strict production configuration parser, but enable only
  // this in-process canary invocation. This does not mutate Worker bindings.
  const config = parseDeliveryRuntimeConfig({
    ...env,
    DELIVERY_ENABLED: "true",
    DELIVERY_BATCH_SIZE: "1",
  });
  if (!config.enabled) {
    return response(500, { ok: false, error: "canary_config_disabled" });
  }

  const client = createClient(config.supabaseUrl, config.supabaseServiceRoleKey, {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false,
    },
  });

  const now = new Date();
  const { data: liveRows, error: ledgerError } = await client
    .from("delivery_ledger")
    .select(
      "id,user_id,kind,state,scheduled_for,next_attempt_at,attempt_count,claim_expires_at,transport_started_at",
    )
    .in("state", ["queued", "claimed"]);

  if (ledgerError || !Array.isArray(liveRows)) {
    return response(503, { ok: false, error: "canary_ledger_unavailable" });
  }

  const claimable = (liveRows as LedgerRow[]).filter((row) =>
    isClaimableCanaryRow(row, now),
  );

  if (
    claimable.length !== 1 ||
    claimable[0].id !== requestedJobId ||
    claimable[0].kind !== "daily_reminder" ||
    claimable[0].transport_started_at !== null
  ) {
    return response(409, {
      ok: false,
      error: "canary_queue_guard_failed",
      claimableCount: claimable.length,
    });
  }

  const guardedRow = claimable[0];
  const { data: authResult, error: authError } =
    await client.auth.admin.getUserById(guardedRow.user_id);
  const recipientEmail = authResult.user?.email?.trim().toLowerCase() ?? "";

  if (
    authError ||
    !authResult.user?.email_confirmed_at ||
    recipientEmail !== APPROVED_CANARY_EMAIL
  ) {
    return response(409, { ok: false, error: "canary_recipient_guard_failed" });
  }

  const [{ data: preference, error: preferenceError }, { data: profile, error: profileError }] =
    await Promise.all([
      client
        .from("daily_reminder_preferences")
        .select("daily_enabled")
        .eq("user_id", guardedRow.user_id)
        .maybeSingle(),
      client
        .from("profiles")
        .select("is_suspended")
        .eq("user_id", guardedRow.user_id)
        .maybeSingle(),
    ]);

  if (
    preferenceError ||
    profileError ||
    preference?.daily_enabled !== true ||
    profile?.is_suspended === true
  ) {
    return response(409, { ok: false, error: "canary_consent_guard_failed" });
  }

  const runtime = createSupabaseDeliveryRuntime(config);
  const claimed = await runtime.claim(now, 1);
  if (claimed.length !== 1 || claimed[0].jobId !== requestedJobId) {
    return response(409, { ok: false, error: "canary_claim_guard_failed" });
  }

  const transport = createResendTransport({
    apiKey: config.resendApiKey,
    fromEmail: config.fromEmail,
    siteOrigin: config.siteOrigin,
  });

  const result = await processClaimedDelivery({
    job: claimed[0],
    gateway: runtime,
    recipientResolver: runtime,
    transport,
  });

  const { data: evidence, error: evidenceError } = await client
    .from("delivery_ledger")
    .select("state,provider_result_id,transport_started_at,sent_at,error_code")
    .eq("id", requestedJobId)
    .maybeSingle();

  if (
    evidenceError ||
    result !== "sent" ||
    evidence?.state !== "sent" ||
    typeof evidence.provider_result_id !== "string" ||
    !evidence.provider_result_id
  ) {
    return response(502, {
      ok: false,
      error: "canary_send_not_confirmed",
      result,
      ledgerState: evidence?.state ?? null,
      errorCode: evidence?.error_code ?? null,
    });
  }

  const providerResponse = await fetch(
    `https://api.resend.com/emails/${encodeURIComponent(evidence.provider_result_id)}`,
    {
      method: "GET",
      headers: {
        authorization: `Bearer ${config.resendApiKey}`,
      },
    },
  );

  let providerLastEvent: string | null = null;
  if (providerResponse.ok) {
    const providerBody = (await providerResponse.json().catch(() => null)) as
      | Record<string, unknown>
      | null;
    if (typeof providerBody?.last_event === "string") {
      providerLastEvent = providerBody.last_event;
    }
  }

  return response(200, {
    ok: true,
    result: "sent",
    ledgerState: "sent",
    providerEvidence: providerResponse.ok,
    providerLastEvent,
  });
}
