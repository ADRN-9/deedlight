import { parseDeliveryRuntimeConfig } from "./config.ts";
import { createResendTransport } from "./resend-transport.ts";
import { processClaimedDelivery } from "./run-delivery.ts";
import { createSupabaseDeliveryRuntime } from "./supabase-runtime.ts";

export const DAILY_DELIVERY_CRON = "*/5 * * * *";
export const WEEKLY_DELIVERY_CRON = "0 16 * * 1";

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

  const now = new Date(input.scheduledTime);
  if (Number.isNaN(now.getTime())) {
    throw new Error("Scheduled delivery timestamp is invalid.");
  }

  const runtime = createSupabaseDeliveryRuntime(config);
  const transport = createResendTransport({
    apiKey: config.resendApiKey,
    fromEmail: config.fromEmail,
    siteOrigin: config.siteOrigin,
  });

  if (input.cron === DAILY_DELIVERY_CRON) {
    summary.enqueued = await runtime.enqueueDaily(now, Math.min(config.batchSize * 20, 2000));
  } else {
    summary.enqueued = await runtime.enqueueWeekly(now, 5000);
  }

  const jobs = await runtime.claim(now, config.batchSize);
  summary.claimed = jobs.length;

  for (const job of jobs) {
    try {
      const result = await processClaimedDelivery({
        job,
        gateway: runtime,
        recipientResolver: runtime,
        transport,
        now,
      });
      summary[result] += 1;
    } catch {
      // Do not leak recipient or provider details. The finite claim lease allows a
      // later scheduler invocation to reclaim safely with the same provider key.
      summary.processingErrors += 1;
      console.error("Delivery job processing failed", { jobId: job.jobId, kind: job.kind });
    }
  }

  console.log("Delivery scheduler summary", summary);
  return summary;
}
