import { getPublicProfile } from "@/lib/data/profiles";
import {
  cleanShareDescription,
} from "@/lib/share/site";
import {
  renderShareCard,
  withShareCache,
} from "@/lib/share/render-card";

type RouteContext = {
  params: Promise<{ username: string }>;
};

export async function GET(_request: Request, { params }: RouteContext) {
  const { username } = await params;
  const profile = await getPublicProfile(username);

  if (!profile) {
    return withShareCache(
      renderShareCard({
        eyebrow: "DEEDLIGHT MEMBER",
        title: "Goodness shared through Deedlight.",
        description:
          "Public member pages only appear when a member has chosen to make their profile public.",
        meta: "deedlight.com",
      }),
    );
  }

  const description = cleanShareDescription(
    profile.bio,
    `${profile.display_name} shares goodness through Deedlight.`,
    180,
  );

  const meta =
    profile.show_contribution_stats === false
      ? `@${profile.username}`
      : `@${profile.username} · ${Number(
          profile.published_offering_count || 0,
        )} public Offerings`;

  return withShareCache(
    renderShareCard({
      eyebrow: "DEEDLIGHT MEMBER",
      title: profile.display_name,
      description,
      meta,
    }),
  );
}
