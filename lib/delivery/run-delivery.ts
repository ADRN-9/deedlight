import type {
  ClaimedDeliveryJob,
  DeliveryGateway,
  DeliveryRecipientResolver,
  DeliveryTransport,
} from "./types.ts";

const RETRY_DELAY_MS = 5 * 60 * 1000;
const PROVIDER_IDEMPOTENCY_SAFETY_MS = 23 * 60 * 60 * 1000;

export type DeliveryProcessingResult =
  | "cancelled"
  | "sent"
  | "retried"
  | "failed";

export async function processClaimedDelivery(input: {
  job: ClaimedDeliveryJob;
  gateway: DeliveryGateway;
  recipientResolver: DeliveryRecipientResolver;
  transport: DeliveryTransport;
  now: Date;
}): Promise<DeliveryProcessingResult> {
  const { job, gateway, recipientResolver, transport, now } = input;

  if (!(await gateway.authorize(job))) {
    return "cancelled";
  }

  const recipient = await recipientResolver.resolve(job.userId);
  if (!recipient?.email) {
    await gateway.markFailed(job, "recipient_email_unavailable");
    return "failed";
  }

  // Consent/suspension can change while recipient lookup occurs. Re-authorize
  // immediately before beginning the external side effect.
  if (!(await gateway.authorize(job))) {
    return "cancelled";
  }

  const firstTransportAt = await gateway.beginTransport(job);
  const elapsed = now.getTime() - firstTransportAt.getTime();

  if (elapsed < 0 || elapsed >= PROVIDER_IDEMPOTENCY_SAFETY_MS) {
    await gateway.markFailed(job, "provider_idempotency_window_expired");
    return "failed";
  }

  const outcome = await transport.send(job, recipient);

  if (outcome.status === "sent") {
    await gateway.markSent(job, outcome.providerResultId);
    return "sent";
  }

  if (outcome.status === "permanent_failure") {
    await gateway.markFailed(job, outcome.errorCode);
    return "failed";
  }

  const retryAt = new Date(now.getTime() + RETRY_DELAY_MS);
  if (retryAt.getTime() >= firstTransportAt.getTime() + PROVIDER_IDEMPOTENCY_SAFETY_MS) {
    await gateway.markFailed(job, "provider_idempotency_window_expired");
    return "failed";
  }

  await gateway.retry(job, retryAt, outcome.errorCode);
  return "retried";
}
