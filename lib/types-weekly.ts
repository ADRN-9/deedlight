import type { Offering } from "@/lib/types";

export type WeeklyOffering = Offering & {
  weekly_bless_count: number;
  weekly_inspired_count: number;
  weekly_carried_forward_count: number;
  weekly_reaction_count: number;
};

export type WeeklyFeature = {
  week_start: string;
  offering: Offering;
};

export type WeeklyFeatureOption = {
  id: string;
  title: string;
  is_anonymous: boolean;
  author_name: string | null;
  author_username: string | null;
  published_at: string | null;
};
