import { redirect } from "next/navigation";
import { CreateOfferingForm } from "@/components/offerings/create-offering-form";
import { createClient } from "@/lib/supabase/server";

export default async function NewOfferingPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const supabase = await createClient({ allowMissingEnv: true });
  const { data } = supabase ? await supabase.auth.getUser() : { data: { user: null } };
  const params = await searchParams;

  if (supabase && !data.user) redirect("/login?next=/offerings/new");

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
