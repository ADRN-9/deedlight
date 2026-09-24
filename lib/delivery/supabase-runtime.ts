import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import type { EnabledDeliveryRuntimeConfig } from "./config.ts";
import type {
  AuthorizedRecipient,
  ClaimedDeliveryJob,
  DeliveryGateway,
  DeliveryRecipientResolver,
} from "./types.ts";

function fail(operation: string): never {
  throw new Error(`Delivery database operation failed: ${operation}`);
}

function parseClaimedJob(row: Record<string, unknown>): ClaimedDeliveryJob {
  const jobId = typeof row.job_id === "string" ? row.job_id : "";
  const userId = typeof row.user_id === "string" ? row.user_id : "";
  const kind = row.kind;
  const deliveryKey = typeof row.delivery_key === "string" ? row.delivery_key : "";
  const scheduledFor = typeof row.scheduled_for === "string" ? row.scheduled_for : "";
  const claimToken = typeof row.claim_token === "string" ? row.claim_token : "";

  if (
    !jobId ||
    !userId ||
    (kind !== "daily_reminder" && kind !== "weekly_newsletter") ||
    !deliveryKey ||
    !scheduledFor ||
    !claimToken
  ) {
    throw new Error("Delivery claim returned an invalid shape.");
  }

  return {
    jobId,
    userId,
    kind,
    deliveryKey,
    scheduledFor,
    claimToken,
  };
}

export class SupabaseDeliveryRuntime implements DeliveryGateway, DeliveryRecipientResolver {
  private readonly client: SupabaseClient;

  constructor(client: SupabaseClient) {
    this.client = client;
  }

  async enqueueDaily(now: Date, limit: number) {
    const { data, error } = await this.client.rpc("enqueue_due_daily_reminders", {
      p_now: now.toISOString(),
      p_limit: limit,
    });
    if (error || typeof data !== "number") fail("enqueue daily reminders");
    return data;
  }

  async enqueueWeekly(now: Date, limit: number) {
    const { data, error } = await this.client.rpc("enqueue_current_weekly_goodness_if_curated", {
      p_now: now.toISOString(),
      p_limit: limit,
    });
    if (error || typeof data !== "number") fail("enqueue weekly goodness");
    return data;
  }

  async claim(now: Date, limit: number): Promise<ClaimedDeliveryJob[]> {
    const { data, error } = await this.client.rpc("claim_delivery_jobs", {
      p_now: now.toISOString(),
      p_limit: limit,
    });
    if (error || !Array.isArray(data)) fail("claim jobs");
    return data.map((row) => parseClaimedJob(row as Record<string, unknown>));
  }

  async authorize(job: ClaimedDeliveryJob): Promise<boolean> {
    const { data, error } = await this.client.rpc("authorize_delivery_job", {
      p_job_id: job.jobId,
      p_claim_token: job.claimToken,
    });
    if (error || typeof data !== "boolean") fail("authorize job");
    return data;
  }

  async beginTransport(job: ClaimedDeliveryJob): Promise<Date> {
    const { data, error } = await this.client.rpc("begin_delivery_transport", {
      p_job_id: job.jobId,
      p_claim_token: job.claimToken,
    });
    if (error || typeof data !== "string") fail("begin transport");

    const startedAt = new Date(data);
    if (Number.isNaN(startedAt.getTime())) fail("parse transport timestamp");
    return startedAt;
  }

  async markSent(job: ClaimedDeliveryJob, providerResultId: string): Promise<void> {
    const { data, error } = await this.client.rpc("mark_delivery_sent", {
      p_job_id: job.jobId,
      p_claim_token: job.claimToken,
      p_provider_result_id: providerResultId,
    });
    if (error || data !== true) fail("mark sent");
  }

  async markFailed(job: ClaimedDeliveryJob, errorCode: string): Promise<void> {
    const { data, error } = await this.client.rpc("mark_delivery_failed", {
      p_job_id: job.jobId,
      p_claim_token: job.claimToken,
      p_error_code: errorCode,
    });
    if (error || data !== true) fail("mark failed");
  }

  async retry(job: ClaimedDeliveryJob, retryAt: Date, errorCode: string): Promise<void> {
    const { data, error } = await this.client.rpc("retry_delivery_job", {
      p_job_id: job.jobId,
      p_claim_token: job.claimToken,
      p_retry_at: retryAt.toISOString(),
      p_error_code: errorCode,
    });
    if (error || data !== true) fail("retry job");
  }

  async resolve(userId: string): Promise<AuthorizedRecipient | null> {
    const { data, error } = await this.client.auth.admin.getUserById(userId);
    if (error) fail("resolve recipient");

    const email = data.user?.email?.trim();
    if (!email || !data.user?.email_confirmed_at) {
      return null;
    }

    return { email };
  }
}

export function createSupabaseDeliveryRuntime(config: EnabledDeliveryRuntimeConfig) {
  const client = createClient(config.supabaseUrl, config.supabaseServiceRoleKey, {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false,
    },
    global: {
      headers: {
        "X-Client-Info": "deedlight-delivery-worker",
      },
    },
  });

  return new SupabaseDeliveryRuntime(client);
}
