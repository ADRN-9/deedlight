export type DailyStatus = "draft" | "scheduled" | "published" | "archived";

export type DailyVideoStatus = "idea" | "scripted" | "recorded" | "published";

export type DailyPost = {
  id: string;
  slug: string | null;
  scheduled_for: string;
  status: DailyStatus;
  kicker: string | null;
  title: string;
  theme: string | null;
  summary: string | null;
  body: string | null;
  small_deed: string | null;
  reflection_prompt: string | null;
  featured_offering_id: string | null;
  image_url: string | null;
  video_title: string | null;
  video_hook: string | null;
  video_script: string | null;
  video_caption: string | null;
  youtube_url: string | null;
  video_status: DailyVideoStatus | null;
  published_at: string | null;
  archived_at: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
  featured_offering?: FeaturedOffering | null;
};

export type FeaturedOffering = {
  id: string;
  title: string;
  story: string | null;
  small_deed: string | null;
  offering_type: string | null;
  author_display_name?: string | null;
  bless_count?: number | null;
  inspired_count?: number | null;
  carried_forward_count?: number | null;
  bless_score?: number | null;
};

export type DailyReflection = {
  id: string;
  user_id: string;
  daily_post_id: string;
  reflection_text: string | null;
  did_today_deed: boolean;
  mood_label: string | null;
  is_private: boolean;
  created_at: string;
  updated_at: string;
};

export type DailyPostWithMeta = DailyPost & {
  reflection_count?: number;
  completed_count?: number;
};
