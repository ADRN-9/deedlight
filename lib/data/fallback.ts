import type { DailyPost, Offering } from "@/lib/types";

export const fallbackDailyPost: DailyPost = {
  id: "fallback-today",
  date: new Date().toISOString().slice(0, 10),
  slug: "protect-someones-dignity",
  title: "Protect someone’s dignity",
  reflection:
    "Beauty is not only found in nature. Sometimes beauty appears when one person refuses to join cruelty.",
  daily_action: "Say one gentle sentence in defense of someone who is being judged unfairly.",
  reflection_question: "Did I make one place safer for goodness today?",
  image_url: null,
  youtube_url: null,
  theme_name: "Courage"
};

export const fallbackOfferings: Offering[] = [
  {
    id: "example-1",
    user_id: "example",
    title: "A small kindness at the bus stop",
    body:
      "I helped someone carry heavy bags today. It was a small moment, but it reminded me that we do not need a big stage to become useful to someone.",
    takeaway: "Look for one small burden you can make lighter today.",
    offering_type: "quiet_goodness",
    media_url: null,
    is_anonymous: true,
    bless_count: 84,
    inspired_count: 12,
    carried_forward_count: 5,
    reflection_count: 3,
    bless_score: 151,
    published_at: new Date().toISOString(),
    theme_name: "Kindness",
    author_name: null
  },
  {
    id: "example-2",
    user_id: "example",
    title: "Call someone who feels forgotten",
    body:
      "Today, I want to invite everyone to call one person who may feel alone. No advice. No lecture. Just presence.",
    takeaway: "One call can remind someone they still matter.",
    offering_type: "goodness_invitation",
    media_url: null,
    is_anonymous: false,
    bless_count: 203,
    inspired_count: 88,
    carried_forward_count: 41,
    reflection_count: 17,
    bless_score: 706,
    published_at: new Date().toISOString(),
    theme_name: "Mercy",
    author_name: "Deedlight Team"
  }
];
