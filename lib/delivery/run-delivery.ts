import type {
  ClaimedDeliveryJob,
  DeliveryGateway,
  DeliveryRecipientResolver,
  DeliveryTransport,
} from "./types.ts";


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
}): Promise<DeliveryProcessingResult> {
  const {
    job,
    gateway,
    recipientResolver,
    transport,
  } = input;

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

  if (await gateway.beginTransport(job, recipient) === null) return "cancelled";

  // Final DB gate rechecks the exact recipient, consent, suspension, suppression and provider horizon.
  const idempotencyAuthorization = await gateway.authorizeProviderIdempotencyWindow(job, recipient);
  if (idempotencyAuthorization === "cancelled") return "cancelled";
  if (idempotencyAuthorization === "expired") return "failed";
  if (idempotencyAuthorization !== "authorized") {
    throw new Error("Provider idempotency authorization returned an unsupported result.");
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

  const requeued = await gateway.retry(job, outcome.errorCode);
  return requeued ? "retried" : "failed";
}
