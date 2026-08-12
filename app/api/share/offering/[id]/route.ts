import { getOffering } from "@/lib/data/offerings";
import {
  cleanShareDescription,
} from "@/lib/share/site";
import {
  renderShareCard,
  withShareCache,
} from "@/lib/share/render-card";

type RouteContext = {
  params: Promise<{ id: string }>;
};

export async function GET(_request: Request, { params }: RouteContext) {
  const { id } = await params;
  const offering = await getOffering(id);

  if (!offering) {
    return withShareCache(
      renderShareCard({
        eyebrow: "DEEDLIGHT OFFERING",
        title: "A light shared through Deedlight.",
        description:
          "Goodness shared with dignity, care, and room for others to carry it forward.",
        meta: "deedlight.com/offerings",
      }),
    );
  }

  const description = cleanShareDescription(
    offering.body,
    "A Deedlight Offering.",
    180,
  );

  return withShareCache(
    renderShareCard({
      eyebrow: "DEEDLIGHT OFFERING",
      title: offering.title,
      description,
      meta: `${Number(offering.bless_count || 0)} blessed · ${Number(
        offering.inspired_count || 0,
      )} inspired · ${Number(
        offering.carried_forward_count || 0,
      )} carried forward`,
    }),
  );
}
