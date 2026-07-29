import Link from "next/link";

type AdminCardProps = {
  href: string;
  eyebrow: string;
  title: string;
  description: string;
  metric?: number | string | null;
  metricLabel?: string;
  tone?: "amber" | "sky" | "emerald" | "stone";
};

const toneStyles = {
  amber: "from-amber-100 via-[#fff8ea] to-white",
  sky: "from-sky-100 via-[#fff8ea] to-white",
  emerald: "from-emerald-100 via-[#fff8ea] to-white",
  stone: "from-stone-100 via-[#fff8ea] to-white",
};

export function AdminCard({
  href,
  eyebrow,
  title,
  description,
  metric,
  metricLabel,
  tone = "amber",
}: AdminCardProps) {
  return (
    <Link
      href={href}
      className={`group block rounded-[2rem] border border-amber-100 bg-gradient-to-br p-6 shadow-[0_24px_70px_rgba(42,32,16,0.06)] transition hover:-translate-y-0.5 hover:shadow-[0_30px_85px_rgba(42,32,16,0.10)] active:scale-[0.99] ${toneStyles[tone]}`}
    >
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="text-xs font-black uppercase tracking-[0.24em] text-amber-800">
            {eyebrow}
          </p>
          <h2 className="mt-3 text-2xl font-black tracking-tight text-stone-950">
            {title}
          </h2>
        </div>
        <span className="rounded-full bg-white px-3 py-2 text-sm font-black text-stone-950 shadow-sm transition group-hover:bg-amber-400">
          Open
        </span>
      </div>

      <p className="mt-4 min-h-14 text-sm leading-7 text-stone-700">
        {description}
      </p>

      {metric !== undefined && metric !== null ? (
        <div className="mt-6 rounded-3xl bg-white/75 p-4">
          <p className="text-3xl font-black text-stone-950">{metric}</p>
          {metricLabel ? (
            <p className="mt-1 text-xs font-black uppercase tracking-[0.22em] text-amber-800">
              {metricLabel}
            </p>
          ) : null}
        </div>
      ) : null}
    </Link>
  );
}
