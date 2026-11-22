// OpenNext generates this module at build time.
// @ts-expect-error OpenNext generates this module during packaging
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

const worker = {
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

export default worker;

// Required by OpenNext when these cache handlers are generated.
// @ts-expect-error OpenNext generates this module during packaging
export { DOQueueHandler, DOShardedTagCache } from "./.open-next/worker.js";
