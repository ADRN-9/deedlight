import { createClient } from "@supabase/supabase-js";

import {
  fingerprintResendWebhookPayload,
  parseResendProviderEvent,
  verifyResendWebhookSignature,
} from "../../../../lib/delivery/resend-webhook.ts";

const MAX_BODY_BYTES = 64 * 1024;

type BodyReadResult =
  | { status: "ok"; value: string }
  | { status: "invalid" }
  | { status: "too_large" };

function response(status: number) {
  return new Response(null, { status });
}

async function readBoundedBody(request: Request): Promise<BodyReadResult> {
  const contentLength = request.headers.get("content-length");
  if (contentLength !== null) {
    if (!/^[0-9]+$/.test(contentLength)) return { status: "invalid" };
    if (Number(contentLength) > MAX_BODY_BYTES) return { status: "too_large" };
  }

  if (!request.body) return { status: "ok", value: "" };
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_BODY_BYTES) {
        try {
          await reader.cancel();
        } catch {
          // The body is already rejected.
        }
        return { status: "too_large" };
      }
      chunks.push(value);
    }
  } catch {
    return { status: "invalid" };
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }

  try {
    return {
      status: "ok",
      value: new TextDecoder("utf-8", { fatal: true }).decode(bytes),
    };
  } catch {
    return { status: "invalid" };
  }
}

export async function POST(request: Request): Promise<Response> {
  const webhookSecret = process.env.RESEND_WEBHOOK_SECRET?.trim() ?? "";
  const supabaseUrl = process.env.SUPABASE_URL?.trim() ?? "";
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim() ?? "";

  if (!webhookSecret || !supabaseUrl || !serviceRoleKey) return response(503);

  let parsedUrl: URL;
  try {
    parsedUrl = new URL(supabaseUrl);
  } catch {
    return response(503);
  }
  if (parsedUrl.protocol !== "https:"
    || !parsedUrl.hostname.endsWith(".supabase.co")
    || parsedUrl.username
    || parsedUrl.password) {
    return response(503);
  }

  const bodyRead = await readBoundedBody(request);
  if (bodyRead.status === "too_large") return response(413);
  if (bodyRead.status === "invalid") return response(400);
  const payload = bodyRead.value;

  const headers = {
    id: request.headers.get("svix-id"),
    timestamp: request.headers.get("svix-timestamp"),
    signature: request.headers.get("svix-signature"),
  };
  if (!(await verifyResendWebhookSignature({ payload, headers, secret: webhookSecret }))) {
    return response(401);
  }

  let eventBody: unknown;
  try {
    eventBody = JSON.parse(payload);
  } catch {
    return response(400);
  }

  let result;
  try {
    result = parseResendProviderEvent(eventBody, headers.id ?? "");
  } catch {
    return response(400);
  }

  if (result.status === "ignored") return response(204);

  let payloadFingerprint: string;
  try {
    payloadFingerprint = await fingerprintResendWebhookPayload(payload);
  } catch {
    return response(503);
  }

  try {
    const client = createClient(parsedUrl.origin, serviceRoleKey, {
      auth: {
        autoRefreshToken: false,
        detectSessionInUrl: false,
        persistSession: false,
      },
    });

    const { data, error } = await client.rpc("record_delivery_provider_lifecycle_event", {
      p_event_id: result.event.eventId,
      p_event_type: result.event.eventType,
      p_provider_email_id: result.event.providerEmailId,
      p_recipient_email: result.event.recipientEmail,
      p_provider_created_at: result.event.providerCreatedAt,
      p_bounce_type: result.event.bounceType,
      p_failure_class: result.event.failureClass,
      p_suppression_reason: result.event.suppressionReason,
      p_payload_fingerprint: payloadFingerprint,
    });

    if (error || (data !== true && data !== false)) return response(503);
  } catch {
    // Database transport failures must remain retryable and must not leak details.
    return response(503);
  }

  return response(204);
}
