import { buildDeliveryMessage } from "./message.ts";
import type {
  AuthorizedRecipient,
  ClaimedDeliveryJob,
  DeliveryTransport,
  DeliveryTransportOutcome,
} from "./types.ts";

export type ResendTransportConfig = {
  apiKey: string;
  fromEmail: string;
  siteOrigin: string;
  timeoutMs?: number;
};

type FetchLike = typeof fetch;

function providerIdIsValid(value: unknown): value is string {
  return typeof value === "string" && value.length >= 1 && value.length <= 255;
}

function idempotencyKey(job: ClaimedDeliveryJob) {
  const key = `deedlight/${job.kind}/${job.jobId}`;
  if (key.length > 256) {
    throw new Error("Delivery idempotency key is unexpectedly too long.");
  }
  return key;
}

async function classifyProviderFailure(response: Response): Promise<DeliveryTransportOutcome> {
  if (response.status === 408 || response.status === 429 || response.status >= 500) {
    return { status: "temporary_failure", errorCode: `provider_http_${response.status}` };
  }

  if (response.status === 409) {
    let name = "";
    try {
      const payload = (await response.json()) as { name?: unknown };
      name = typeof payload?.name === "string" ? payload.name : "";
    } catch {
      // A malformed conflict response is ambiguous and safe to retry idempotently.
    }

    if (name === "concurrent_idempotent_requests" || !name) {
      return { status: "temporary_failure", errorCode: "provider_idempotency_in_progress" };
    }

    return { status: "permanent_failure", errorCode: "provider_idempotency_conflict" };
  }

  if (response.status === 401 || response.status === 403) {
    return { status: "permanent_failure", errorCode: "provider_auth_rejected" };
  }

  return { status: "permanent_failure", errorCode: `provider_http_${response.status}` };
}

export function createResendTransport(
  config: ResendTransportConfig,
  fetchImpl: FetchLike = fetch,
): DeliveryTransport {
  const timeoutMs = config.timeoutMs ?? 15_000;

  if (timeoutMs < 1 || timeoutMs > 30_000) {
    throw new Error("Resend transport timeout must be between 1 and 30000 ms.");
  }

  return {
    async send(
      job: ClaimedDeliveryJob,
      recipient: AuthorizedRecipient,
    ): Promise<DeliveryTransportOutcome> {
      const message = buildDeliveryMessage(job, config.siteOrigin);

      let response: Response;
      try {
        response = await fetchImpl("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${config.apiKey}`,
            "Content-Type": "application/json",
            "Idempotency-Key": idempotencyKey(job),
          },
          body: JSON.stringify({
            from: config.fromEmail,
            to: [recipient.email],
            subject: message.subject,
            text: message.text,
            html: message.html,
          }),
          signal: AbortSignal.timeout(timeoutMs),
        });
      } catch (error) {
        const errorName = error instanceof Error ? error.name : "";
        return {
          status: "temporary_failure",
          errorCode: errorName === "TimeoutError" ? "provider_timeout" : "provider_network_error",
        };
      }

      if (!response.ok) {
        return classifyProviderFailure(response);
      }

      try {
        const payload = (await response.json()) as { id?: unknown };
        if (!providerIdIsValid(payload?.id)) {
          return { status: "temporary_failure", errorCode: "provider_ambiguous_response" };
        }
        return { status: "sent", providerResultId: payload.id };
      } catch {
        return { status: "temporary_failure", errorCode: "provider_ambiguous_response" };
      }
    },
  };
}
