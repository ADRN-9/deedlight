import Link from "next/link";

type AdminEmptyStateProps = {
  title: string;
  description: string;
  href?: string;
  actionLabel?: string;
};

export function AdminEmptyState({
  title,
  description,
  href,
  actionLabel,
}: AdminEmptyStateProps) {
  return (
    <section className="rounded-[2rem] border border-amber-100 bg-white p-8 text-center shadow-[0_24px_70px_rgba(42,32,16,0.06)]">
      <p className="mx-auto flex h-12 w-12 items-center justify-center rounded-2xl bg-amber-100 text-xl">
        ✦
      </p>
      <h2 className="mt-4 text-2xl font-black tracking-tight text-stone-950">
        {title}
      </h2>
      <p className="mx-auto mt-2 max-w-lg text-sm leading-7 text-stone-600">
        {description}
      </p>
      {href && actionLabel ? (
        <Link
          href={href}
          className="mt-6 inline-flex rounded-full bg-amber-400 px-6 py-3 text-sm font-black text-stone-950 shadow-lg shadow-amber-200 transition hover:bg-amber-500 active:scale-[0.98]"
        >
          {actionLabel}
        </Link>
      ) : null}
    </section>
  );
}
