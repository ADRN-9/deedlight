import { createClient } from "@supabase/supabase-js";
import {
  InvalidResendWebhook,
  verifyResendDeliveryWebhook,
} from "@/lib/delivery/resend-webhook";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const MAX_WEBHOOK_BYTES = 128 * 1024;

async function readLimitedRawBody(request: Request): Promise<string> {
  if (!request.body) throw new InvalidResendWebhook("Missing webhook body");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let bytes = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > MAX_WEBHOOK_BYTES) {
        await reader.cancel();
        throw new InvalidResendWebhook("Webhook payload exceeds size limit");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const raw = new Uint8Array(bytes);
  let offset = 0;
  for (const chunk of chunks) {
    raw.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(raw);
  } catch {
    throw new InvalidResendWebhook("Webhook payload is not valid UTF-8");
  }
}

function isValidSupabaseUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === "https:"
      && /^[a-z0-9-]+\.supabase\.co$/.test(url.hostname)
      && !url.username && !url.password && !url.port
      && (url.pathname === "/" || url.pathname === "")
      && !url.search && !url.hash;
  } catch {
    return false;
  }
}

const responseHeaders = {
  "Cache-Control": "no-store",
  "Content-Type": "text/plain; charset=utf-8",
};

export async function POST(request: Request): Promise<Response> {
  const secret = process.env.RESEND_WEBHOOK_SECRET;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const supabaseUrl = process.env.SUPABASE_URL;
  if (!secret || !serviceRoleKey || !supabaseUrl || !isValidSupabaseUrl(supabaseUrl)) {
    return new Response("Webhook unavailable", { status: 503, headers: responseHeaders });
  }
  const declaredLength = Number(request.headers.get("content-length") || "0");
  if (!Number.isSafeInteger(declaredLength) || declaredLength > 128 * 1024) {
    return new Response("Payload too large", { status: 413, headers: responseHeaders });
  }
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
    return new Response("Unsupported media type", { status: 415, headers: responseHeaders });
  }

  let event;
  try {
    event = await verifyResendDeliveryWebhook({
      rawBody: await readLimitedRawBody(request),
      headers: request.headers,
      secret,
    });
  } catch (error) {
    if (error instanceof InvalidResendWebhook) {
      return new Response("Invalid webhook", { status: 400, headers: responseHeaders });
    }
    return new Response("Webhook unavailable", { status: 503, headers: responseHeaders });
  }

  try {
    const client = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, detectSessionInUrl: false, persistSession: false },
    });
    const operation = event.kind === "account_suppression"
      ? "deedlight_record_resend_suppression_verified"
      : "deedlight_record_resend_delivery_v2";
    const args = event.kind === "account_suppression"
      ? {
          p_event_id: event.eventId,
          p_suppression_id: event.suppressionId,
          p_recipient_email: event.recipientEmail,
          p_origin: event.origin,
          p_source_id: event.sourceId,
          p_event_type: event.eventType,
          p_event_at: event.eventAt,
          p_payload_sha256: event.payloadSha256,
        }
      : {
          p_event_id: event.eventId,
          p_provider_email_id: event.providerEmailId,
          p_recipient_email: event.recipientEmail,
          p_event_type: event.eventType,
          p_event_at: event.eventAt,
          p_payload_sha256: event.payloadSha256,
          p_suppression_reason: event.suppressionReason,
          p_bounce_type: event.bounceType,
        };
    const { data, error } = await client.rpc(operation, args);
    if (error || !["recorded", "pending", "duplicate", "quarantined"].includes(data)) {
      return new Response("Webhook temporarily unavailable", { status: 503, headers: responseHeaders });
    }
    // Acknowledged only after durable DB COMMIT, including pending/quarantine.
    return new Response("Accepted", { status: data === "pending" ? 202 : 200, headers: responseHeaders });
  } catch {
    return new Response("Webhook temporarily unavailable", { status: 503, headers: responseHeaders });
  }
}
