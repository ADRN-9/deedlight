import { parseDeliveryRuntimeConfig } from "./config.ts";
import { createResendTransport } from "./resend-transport.ts";
import { processClaimedDelivery } from "./run-delivery.ts";
import {
  createSupabaseDeliveryRuntime,
  WeeklyDeliveryCapacityError,
  weeklyIssueStartUtc,
} from "./supabase-runtime.ts";

export const DAILY_DELIVERY_CRON = "*/5 * * * *";
export const WEEKLY_DELIVERY_CRON = "0 16 * * MON";

export type DeliverySchedulerSummary = {
  enabled: boolean;
  cron: string;
  enqueued: number;
  claimed: number;
  sent: number;
  retried: number;
  failed: number;
  cancelled: number;
  processingErrors: number;
  ignored: boolean;
};

// Enqueue rejection is terminal for this invocation: no claims or provider IO.
export async function enqueueWeeklyWithMonitoring(
  enqueue: (now: Date, limit: number) => Promise<number>,
  scheduledAt: Date,
  limit: number,
  logError: (message: string, context: { code: string; weekStart: string }) => void =
    (message, context) => console.error(message, context),
): Promise<number> {
  try {
    return await enqueue(scheduledAt, limit);
  } catch (error) {
    const capacity = error instanceof WeeklyDeliveryCapacityError;
    logError("Weekly Goodness enqueue failed", {
      code: capacity ? error.code : "weekly_enqueue_database_error",
      weekStart: weeklyIssueStartUtc(scheduledAt),
    });
    if (capacity) throw error;
    throw new Error("Delivery database operation failed: enqueue weekly goodness");
  }
}

export async function runScheduledDelivery(
  env: Record<string, string | undefined>,
  input: { cron: string; scheduledTime: number },
): Promise<DeliverySchedulerSummary> {
  const summary: DeliverySchedulerSummary = {
    enabled: false,
    cron: input.cron,
    enqueued: 0,
    claimed: 0,
    sent: 0,
    retried: 0,
    failed: 0,
    cancelled: 0,
    processingErrors: 0,
    ignored: false,
  };

  const config = parseDeliveryRuntimeConfig(env);
  if (!config.enabled) {
    return summary;
  }
  summary.enabled = true;

  if (input.cron !== DAILY_DELIVERY_CRON && input.cron !== WEEKLY_DELIVERY_CRON) {
    summary.ignored = true;
    return summary;
  }

  const scheduledAt = new Date(input.scheduledTime);
  if (Number.isNaN(scheduledAt.getTime())) {
    throw new Error("Scheduled delivery timestamp is invalid.");
  }

  // Cloudflare scheduledTime is the original UTC schedule instant. Ignore
  // displaced/synthetic cron claims rather than running the wrong delivery kind.
  if (scheduledAt.getUTCSeconds() !== 0 || scheduledAt.getUTCMilliseconds() !== 0
    || (input.cron === DAILY_DELIVERY_CRON && scheduledAt.getUTCMinutes() % 5 !== 0)
    || (input.cron === WEEKLY_DELIVERY_CRON && (
      scheduledAt.getUTCDay() !== 1 || scheduledAt.getUTCHours() !== 16
      || scheduledAt.getUTCMinutes() !== 0))) {
    summary.ignored = true;
    return summary;
  }

  const runtime = createSupabaseDeliveryRuntime(config);
  const transport = createResendTransport({
    apiKey: config.resendApiKey,
    fromEmail: config.fromEmail,
    siteOrigin: config.siteOrigin,
  });

  if (input.cron === DAILY_DELIVERY_CRON) {
    summary.enqueued = await runtime.enqueueDaily(
      scheduledAt,
      Math.min(config.batchSize * 20, 2000),
    );
  } else {
    summary.enqueued = await enqueueWeeklyWithMonitoring(
      (at, limit) => runtime.enqueueWeekly(at, limit),
      scheduledAt,
      5000,
    );
  }

  const claimKind = input.cron === DAILY_DELIVERY_CRON
    ? "daily_reminder"
    : "weekly_newsletter";
  const jobs = await runtime.claim(claimKind, scheduledAt, config.batchSize);
  summary.claimed = jobs.length;

  for (const job of jobs) {
    try {
      const result = await processClaimedDelivery({
        job,
        gateway: runtime,
        recipientResolver: runtime,
        transport,
      });
      summary[result] += 1;
    } catch {
      // Do not leak recipient or provider details. The finite claim lease allows a
      // later scheduler invocation to reclaim safely with the same provider key.
      summary.processingErrors += 1;
      console.error("Delivery job processing failed", {
        kind: job.kind,
      });
    }
  }

  console.log("Delivery scheduler summary", summary);
  return summary;
}
