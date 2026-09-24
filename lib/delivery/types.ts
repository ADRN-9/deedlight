export type DeliveryKind = "daily_reminder" | "weekly_newsletter";

export type ClaimedDeliveryJob = {
  jobId: string;
  userId: string;
  kind: DeliveryKind;
  deliveryKey: string;
  scheduledFor: string;
  claimToken: string;
};

export type AuthorizedRecipient = {
  email: string;
};

export type DeliveryTransportOutcome =
  | { status: "sent"; providerResultId: string }
  | { status: "temporary_failure"; errorCode: string }
  | { status: "permanent_failure"; errorCode: string };

export interface DeliveryGateway {
  authorize(job: ClaimedDeliveryJob): Promise<boolean>;
  beginTransport(job: ClaimedDeliveryJob): Promise<Date>;
  markSent(job: ClaimedDeliveryJob, providerResultId: string): Promise<void>;
  markFailed(job: ClaimedDeliveryJob, errorCode: string): Promise<void>;
  retry(job: ClaimedDeliveryJob, retryAt: Date, errorCode: string): Promise<void>;
}

export interface DeliveryRecipientResolver {
  resolve(userId: string): Promise<AuthorizedRecipient | null>;
}

export interface DeliveryTransport {
  send(
    job: ClaimedDeliveryJob,
    recipient: AuthorizedRecipient,
  ): Promise<DeliveryTransportOutcome>;
}
