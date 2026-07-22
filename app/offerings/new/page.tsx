import Link from "next/link";
import { CreateOfferingForm } from "@/components/offerings/create-offering-form";
import { createClient } from "@/lib/supabase/server";

type SearchParamsValue = {
  error?: string;
  submitted?: string;
};

type PageProps = {
  searchParams?: Promise<SearchParamsValue> | SearchParamsValue;
};

export const dynamic = "force-dynamic";

async function getSearchParams(searchParams: PageProps["searchParams"]): Promise<SearchParamsValue> {
  if (!searchParams) return {};
  return await Promise.resolve(searchParams);
}

async function getCurrentUserSafely() {
  try {
    const supabase = await createClient({ allowMissingEnv: true });
    if (!supabase) return null;

    const {
      data: { user },
      error
    } = await supabase.auth.getUser();

    if (error) return null;
    return user;
  } catch (error) {
    console.error("Offerings new auth check failed", error);
    return null;
  }
}

export default async function NewOfferingPage({ searchParams }: PageProps) {
  const params = await getSearchParams(searchParams);
  const user = await getCurrentUserSafely();

  if (!user) {
    return (
      <section className="mx-auto max-w-3xl px-4 py-16 sm:px-6">
        <div className="deed-card p-8 text-center sm:p-10">
          <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Share an Offering</p>
          <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">Sign in to prepare a light.</h1>
          <p className="mx-auto mt-4 max-w-2xl leading-8 text-[#7C715F]">
            Offerings are connected to your Goodness Journey and reviewed before they become public, so please sign in first.
          </p>
          <div className="mt-8 flex flex-col justify-center gap-3 sm:flex-row">
            <Link
              href="/login?next=/offerings/new"
              className="focus-ring rounded-full bg-[#D9A441] px-6 py-3 text-sm font-extrabold text-[#26231F]"
            >
              Sign in
            </Link>
            <Link
              href="/signup?next=/offerings/new"
              className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-6 py-3 text-sm font-extrabold text-[#26231F]"
            >
              Join Deedlight
            </Link>
          </div>
        </div>
      </section>
    );
  }

  return (
    <section className="mx-auto max-w-4xl px-4 py-12 sm:px-6">
      <div className="mb-8">
        <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Share an Offering</p>
        <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">Prepare a light with care.</h1>
        <p className="mt-4 max-w-2xl leading-8 text-[#7C715F]">
          Offerings are reviewed before they become public so Deedlight stays safe, dignified, and sincere.
        </p>
      </div>

      <CreateOfferingForm error={params.error} />
    </section>
  );
}
