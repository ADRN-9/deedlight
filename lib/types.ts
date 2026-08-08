export type DailyPost = {
  id: string;
  date: string;
  slug: string;
  title: string;
  reflection: string;
  daily_action: string;
  reflection_question: string | null;
  image_url: string | null;
  youtube_url: string | null;
  theme_name?: string | null;
};

export type ReactionType = "bless" | "inspired_me" | "i_did_this_too";

export type ReactionCounts = {
  bless_count: number;
  inspired_count: number;
  carried_forward_count: number;
};

export type Offering = {
  id: string;
  user_id: string | null;
  title: string;
  body: string;
  takeaway: string | null;
  offering_type: string;
  media_url: string | null;
  media_type?: string | null;
  is_anonymous: boolean;
  allow_reflections?: boolean;
  location_label?: string | null;
  bless_count: number;
  inspired_count: number;
  carried_forward_count: number;
  reflection_count: number;
  bless_score: number;
  rising_score?: number | null;
  published_at: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  theme_name?: string | null;
  author_name?: string | null;
  author_username?: string | null;
};

export type AdminOffering = Offering & {
  theme_id?: string | null;
  status: "draft" | "pending" | "approved" | "rejected" | "needs_edit" | "hidden";
  moderation_note: string | null;
  open_report_count?: number;
};

export type ReportReason =
  | "exposes_vulnerable_person"
  | "hate_or_prejudice"
  | "fake_charity_or_fraud"
  | "harassment"
  | "graphic_or_disturbing"
  | "self_promotion"
  | "privacy_concern"
  | "other";

export type ReportStatus = "open" | "reviewing" | "resolved" | "dismissed";

export type ReportItem = {
  id: string;
  offering_id: string | null;
  reflection_id: string | null;
  reported_by: string | null;
  reason: ReportReason;
  details: string | null;
  status: ReportStatus;
  admin_note: string | null;
  resolved_by: string | null;
  resolved_at: string | null;
  created_at: string;
  reporter_name?: string | null;
  offering?: AdminOffering | null;
};

export type ProfileSummary = {
  user_id: string;
  display_name: string;
  username: string | null;
  avatar_url: string | null;
  role?: string;
};
