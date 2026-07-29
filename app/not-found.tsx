import Link from "next/link";

export default function NotFound() {
  return (
    <div className="mx-auto max-w-2xl px-5 py-20 text-center md:py-28">
      <p className="text-xs font-black uppercase tracking-[0.32em] text-amber-800">
        Page not found
      </p>
      <h1 className="mt-4 text-4xl font-black tracking-tight text-stone-950 md:text-6xl">
        This light is not here.
      </h1>
      <p className="mx-auto mt-4 max-w-lg text-sm leading-7 text-stone-600">
        The page may have moved, been archived, or may only be available to admins.
      </p>
      <div className="mt-7 flex flex-col justify-center gap-3 sm:flex-row">
        <Link
          href="/today"
          className="rounded-full bg-amber-400 px-6 py-3 text-sm font-black text-stone-950 shadow-lg shadow-amber-200 transition hover:bg-amber-500 active:scale-[0.98]"
        >
          Go to Today
        </Link>
        <Link
          href="/offerings"
          className="rounded-full border border-amber-200 bg-white px-6 py-3 text-sm font-black text-stone-950 transition hover:bg-[#fff8ea] active:scale-[0.98]"
        >
          Browse Offerings
        </Link>
      </div>
    </div>
  );
}
