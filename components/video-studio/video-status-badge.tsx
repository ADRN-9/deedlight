type VideoStatusBadgeProps = {
  status?: string | null;
};

const labels: Record<string, string> = {
  not_started: "Not started",
  planned: "Planned",
  scripted: "Scripted",
  recorded: "Recorded",
  posted: "Posted",
  archived: "Archived",
};

const tones: Record<string, string> = {
  not_started: "bg-stone-100 text-stone-700 border-stone-200",
  planned: "bg-amber-50 text-amber-800 border-amber-200",
  scripted: "bg-sky-50 text-sky-800 border-sky-200",
  recorded: "bg-violet-50 text-violet-800 border-violet-200",
  posted: "bg-emerald-50 text-emerald-800 border-emerald-200",
  archived: "bg-stone-100 text-stone-500 border-stone-200",
};

export function VideoStatusBadge({ status }: VideoStatusBadgeProps) {
  const value = status || "not_started";
  return (
    <span
      className={`inline-flex rounded-full border px-3 py-1 text-xs font-black uppercase tracking-[0.16em] ${
        tones[value] ?? tones.not_started
      }`}
    >
      {labels[value] ?? labels.not_started}
    </span>
  );
}

export const videoStatusOptions = [
  { value: "not_started", label: "Not started" },
  { value: "planned", label: "Planned" },
  { value: "scripted", label: "Scripted" },
  { value: "recorded", label: "Recorded" },
  { value: "posted", label: "Posted" },
  { value: "archived", label: "Archived" },
] as const;
