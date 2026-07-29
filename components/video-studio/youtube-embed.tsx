type YouTubeEmbedProps = {
  url?: string | null;
  title?: string | null;
};

function getYouTubeId(value?: string | null) {
  if (!value) return null;

  try {
    const url = new URL(value);
    const hostname = url.hostname.replace(/^www\./, "");

    if (hostname === "youtu.be") {
      return url.pathname.split("/").filter(Boolean)[0] ?? null;
    }

    if (hostname === "youtube.com" || hostname === "m.youtube.com" || hostname === "music.youtube.com") {
      const watchId = url.searchParams.get("v");
      if (watchId) return watchId;

      const parts = url.pathname.split("/").filter(Boolean);
      if (["embed", "shorts", "live"].includes(parts[0] ?? "")) {
        return parts[1] ?? null;
      }
    }
  } catch {
    return null;
  }

  return null;
}

export function YouTubeEmbed({ url, title }: YouTubeEmbedProps) {
  const id = getYouTubeId(url);

  if (!id) return null;

  return (
    <div className="overflow-hidden rounded-[1.75rem] border border-amber-100 bg-stone-950 shadow-[0_24px_70px_rgba(42,32,16,0.12)]">
      <div className="aspect-video w-full">
        <iframe
          className="h-full w-full"
          src={`https://www.youtube-nocookie.com/embed/${id}`}
          title={title || "Deedlight video"}
          allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
          allowFullScreen
        />
      </div>
    </div>
  );
}
