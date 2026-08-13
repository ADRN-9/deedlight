import {
  getCurrentWeeklyFeature,
  getWeeklyGoodness,
} from "@/lib/data/weekly";
import {
  renderShareCard,
  withShareCache,
} from "@/lib/share/render-card";
import { cleanShareDescription } from "@/lib/share/site";

export async function GET() {
  const [feature, offerings] = await Promise.all([
    getCurrentWeeklyFeature(),
    getWeeklyGoodness(1),
  ]);

  const focus = feature?.offering ?? offerings[0] ?? null;

  return withShareCache(
    renderShareCard({
      eyebrow: "WEEKLY GOODNESS",
      title: focus?.title || "A week of light, without a leaderboard.",
      description: cleanShareDescription(
        focus?.body,
        "Public Offerings carrying light across the last seven days — surfaced gently, without ranking people.",
        180,
      ),
      meta: "Last seven days · deedlight.com/weekly",
    }),
  );
}
