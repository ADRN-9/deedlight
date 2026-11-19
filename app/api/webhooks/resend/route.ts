import { createClient } from "@supabase/supabase-js";

import {
  parseResendProviderEvent,
  verifyResendWebhookSignature,
} from "@/lib/delivery/resend-webhook";

const MAX_BODY_BYTES = 64 * 1024;

function response(status: number) {
  return new Response(null, { status });
}

async function readBoundedBody(request: Request): Promise<string | null> {
  const contentLength = request.headers.get("content-length");
  if (contentLength !== null) {
    if (!/^\d+$/.test(contentLength)) return null;
    if (Number(contentLength) > MAX_BODY_BYTES) return null;
  }

  if (!request.body) return "";
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_BODY_BYTES) {
        await reader.cancel();
        return null;
      }
      chunks.push(value);
    }
  } catch {
    return null;
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }

  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return null;
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

  const payload = await readBoundedBody(request);
  if (payload === null) return response(413);

  const headers = {
    id: request.headers.get("svix-id"),
    timestamp: request.headers.get("svix-timestamp"),
    signature: request.headers.get("svix-signature"),
  };
  if (!(await verifyResendWebhookSignature({ payload, headers, secret: webhookSecret }))) {
    return response(401);
  }

  let body: unknown;
  try {
    body = JSON.parse(payload);
  } catch {
    return response(400);
  }

  let result;
  try {
    result = parseResendProviderEvent(body, headers.id ?? "");
  } catch {
    return response(400);
  }

  if (result.status === "ignored") return response(204);

  const client = createClient(parsedUrl.origin, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false,
    },
  });

  const { error } = await client.rpc("record_delivery_provider_event", {
    p_event_id: result.event.eventId,
    p_event_type: result.event.eventType,
    p_provider_email_id: result.event.providerEmailId,
    p_recipient_email: result.event.recipientEmail,
    p_bounce_type: result.event.bounceType,
  });

  if (error) return response(503);
  return response(204);
}
