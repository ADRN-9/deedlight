# Sprint 8 — Short Video Studio

Sprint 8 turns Daily Deedlights into reusable short-video content.

## What this adds

- `/admin/video-studio`
  - Video production dashboard for Daily Deedlights.
  - Status filters: not started, planned, scripted, recorded, posted, archived.
  - Quick visibility of public embeds and platform links.

- `/admin/video-studio/[id]`
  - Edit short-video title, hook, script, caption, hashtags, notes, asset link, YouTube/TikTok/Instagram links.
  - Generate a starter script/caption from the Daily Deedlight content.
  - Copy script and caption/hashtags.
  - Mark a video public.
  - Preview YouTube embed.

- `/videos`
  - Public page for posted, public Deedlight videos.

- `/today`
  - Shows a YouTube embed when the selected Daily Deedlight has:
    - `youtube_url`
    - `short_video_public = true`

## Database migration

Run this in Supabase SQL Editor or through your normal migration flow:

```text
supabase/migrations/202607270008_sprint8_short_video_studio.sql
```

This adds these columns to `public.daily_lights`:

- `video_status`
- `video_platform`
- `video_hashtags`
- `video_notes`
- `video_asset_url`
- `tiktok_url`
- `instagram_url`
- `short_video_public`
- `video_posted_at`

Sprint 6 already added:

- `video_title`
- `video_hook`
- `video_script`
- `video_caption`
- `youtube_url`

## Local test

```powershell
npm run build
npm run dev
```

Test:

```text
/admin/video-studio
/admin/video-studio/YOUR_DAILY_LIGHT_ID
/videos
/today
```

## Acceptance checklist

- Admin can open the Short Video Studio.
- Admin can generate a starter video draft from a Daily Deedlight.
- Admin can save hook/script/caption/hashtags.
- Admin can set video status to planned/scripted/recorded/posted.
- Admin can save a YouTube URL.
- Admin can mark the video public.
- `/videos` shows the public video.
- `/today` shows the video embed when available.
- Build passes locally and on Cloudflare.
