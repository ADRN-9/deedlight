import {
  renderShareCard,
  withShareCache,
} from "@/lib/share/render-card";

export async function GET() {
  return withShareCache(
    renderShareCard({
      eyebrow: "DEEDLIGHT",
      title: "Goodness does not prevail by accident.",
      description:
        "A daily social space where good deeds become light — shared, blessed, and carried forward.",
      meta: "deedlight.com",
    }),
  );
}
