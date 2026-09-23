// OpenNext generates this module at build time.
// @ts-ignore generated worker module is intentionally absent before packaging
import handler from "./.open-next/worker.js";

import { runScheduledDelivery } from "./lib/delivery/scheduler.ts";

type DeliveryWorkerEnv = Record<string, string | undefined>;
type DeliveryScheduledController = {
  cron: string;
  scheduledTime: number;
};
type DeliveryExecutionContext = {
  waitUntil(promise: Promise<unknown>): void;
};

export default {
  fetch: handler.fetch,

  async scheduled(
    controller: DeliveryScheduledController,
    env: DeliveryWorkerEnv,
    ctx: DeliveryExecutionContext,
  ) {
    const work = runScheduledDelivery(env, {
      cron: controller.cron,
      scheduledTime: controller.scheduledTime,
    });
    ctx.waitUntil(work);
    await work;
  },
};

// Required by OpenNext when these cache handlers are generated.
// @ts-ignore generated worker module is intentionally absent before packaging
export { DOQueueHandler, DOShardedTagCache } from "./.open-next/worker.js";
