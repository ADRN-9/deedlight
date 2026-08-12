import { getTodayShareLight } from "@/lib/share/today";
import {
  cleanShareDescription,
} from "@/lib/share/site";
import {
  renderShareCard,
  withShareCache,
} from "@/lib/share/render-card";

export async function GET() {
  const light = await getTodayShareLight();

  if (!light) {
    return withShareCache(
      renderShareCard({
        eyebrow: "TODAY'S DEEDLIGHT",
        title: "A small deed can carry light forward.",
        description:
          "Return to Deedlight for today's invitation to goodness.",
        meta: "deedlight.com/today",
      }),
    );
  }

  const description = cleanShareDescription(
    light.summary || light.small_deed,
    "A daily invitation to goodness, beauty, and better deeds.",
    180,
  );

  return withShareCache(
    renderShareCard({
      eyebrow: light.theme
        ? `TODAY · ${light.theme.toUpperCase()}`
        : "TODAY'S DEEDLIGHT",
      title: light.title || "Today's Deedlight",
      description,
      meta: light.scheduled_date
        ? `${light.scheduled_date} · deedlight.com/today`
        : "deedlight.com/today",
    }),
  );
}
