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

export type Offering = {
  id: string;
  user_id: string;
  title: string;
  body: string;
  takeaway: string | null;
  offering_type: string;
  media_url: string | null;
  is_anonymous: boolean;
  bless_count: number;
  inspired_count: number;
  carried_forward_count: number;
  reflection_count: number;
  bless_score: number;
  published_at: string | null;
  theme_name?: string | null;
  author_name?: string | null;
};
