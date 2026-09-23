import type { ClaimedDeliveryJob } from "./types.ts";

export type DeliveryMessage = {
  subject: string;
  text: string;
  html: string;
};

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

export function buildDeliveryMessage(
  job: ClaimedDeliveryJob,
  siteOrigin: string,
): DeliveryMessage {
  const origin = siteOrigin.replace(/\/$/, "");

  if (job.kind === "daily_reminder") {
    const todayUrl = `${origin}/today`;
    const settingsUrl = `${origin}/settings/reminders`;

    return {
      subject: "A gentle Deedlight reminder",
      text: [
        "Your daily Deedlight is ready when you are.",
        "",
        `Open today’s Deedlight: ${todayUrl}`,
        "",
        `Manage reminders: ${settingsUrl}`,
      ].join("\n"),
      html: [
        "<p>Your daily Deedlight is ready when you are.</p>",
        `<p><a href="${escapeHtml(todayUrl)}">Open today’s Deedlight</a></p>`,
        `<p><a href="${escapeHtml(settingsUrl)}">Manage reminders</a></p>`,
      ].join(""),
    };
  }

  if (job.kind === "weekly_newsletter") {
    const weeklyUrl = `${origin}/weekly`;
    const settingsUrl = `${origin}/settings/newsletter`;

    return {
      subject: "Weekly Goodness from Deedlight",
      text: [
        "A new Weekly Goodness collection is ready.",
        "",
        `Explore Weekly Goodness: ${weeklyUrl}`,
        "",
        `Manage newsletter preferences: ${settingsUrl}`,
      ].join("\n"),
      html: [
        "<p>A new Weekly Goodness collection is ready.</p>",
        `<p><a href="${escapeHtml(weeklyUrl)}">Explore Weekly Goodness</a></p>`,
        `<p><a href="${escapeHtml(settingsUrl)}">Manage newsletter preferences</a></p>`,
      ].join(""),
    };
  }

  const neverKind: never = job.kind;
  throw new Error(`Unsupported delivery kind: ${String(neverKind)}`);
}
