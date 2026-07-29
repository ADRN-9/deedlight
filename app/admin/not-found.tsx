import Link from "next/link";

export default function AdminNotFound() {
  return (
    <div className="mx-auto max-w-2xl px-5 py-20 text-center">
      <p className="text-xs font-black uppercase tracking-[0.28em] text-amber-800">
        Page not found
      </p>
      <h1 className="mt-3 text-4xl font-black tracking-tight text-stone-950 md:text-6xl">
        This admin page is not available.
      </h1>
      <p className="mt-4 text-sm leading-7 text-stone-600">
        The page may have moved, or this account may not have permission to view it.
      </p>
      <Link
        href="/today"
        className="mt-7 inline-flex rounded-full bg-amber-400 px-6 py-3 text-sm font-black text-stone-950 shadow-lg shadow-amber-200 transition hover:bg-amber-500 active:scale-[0.98]"
      >
        Return to Today
      </Link>
    </div>
  );
}
