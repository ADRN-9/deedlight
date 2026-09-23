import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { EditOfferingForm } from "@/components/offerings/edit-offering-form";
import { getMyOffering } from "@/lib/data/offerings";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type EditOfferingPageProps = {
  params: Promise<{ id: string }>;
  searchParams?: Promise<Record<string, string | string[] | undefined>>;
};

function getString(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

export default async function EditOfferingPage({
  params,
  searchParams,
}: EditOfferingPageProps) {
  const { id } = await params;
  const query = searchParams ? await searchParams : {};
  const error = getString(query.error);

  const supabase = await createClient({ allowMissingEnv: true });
  if (!supabase) redirect(`/login?next=${encodeURIComponent(`/offerings/${id}/edit`)}`);

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect(`/login?next=${encodeURIComponent(`/offerings/${id}/edit`)}`);

  const offering = await getMyOffering(id);
  if (!offering) notFound();

  const { data: profile } = await supabase
    .from("profiles")
    .select("is_suspended")
    .eq("user_id", user.id)
    .maybeSingle();

  const moderatorHidden =
    offering.status === "hidden" && !offering.owner_removed_at;

  return (
    <main className="mx-auto max-w-4xl px-4 py-12 sm:px-6 sm:py-16">
      <div className="mb-7 flex flex-wrap items-center justify-between gap-3">
        <Link
          href="/journey#my-offerings"
          className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-5 py-3 text-sm font-extrabold text-[#4B4034] hover:bg-[#FFF8EA]"
        >
          ← Back to My Offerings
        </Link>
        <span className="rounded-full bg-[#FFF8EA] px-4 py-2 text-xs font-extrabold uppercase tracking-[0.16em] text-[#8D681D]">
          {offering.owner_removed_at ? "Removed by you" : offering.status.replace("_", " ")}
        </span>
      </div>

      <section className="deed-card p-6 sm:p-9">
        <p className="text-xs font-extrabold uppercase tracking-[0.28em] text-[#8D681D]">
          Edit your Offering
        </p>
        <h1 className="mt-3 font-[var(--font-heading)] text-4xl font-semibold leading-tight sm:text-5xl">
          Refine the light, keep the trust.
        </h1>
        <p className="mt-4 max-w-2xl leading-8 text-[#5F5548]">
          You control your own Offering, while moderation continues to protect dignity, privacy, and community safety.
        </p>

        {error ? (
          <div className="mt-6 rounded-2xl border border-red-100 bg-red-50 p-4 text-sm font-bold leading-6 text-red-900">
            {error}
          </div>
        ) : null}

        {profile?.is_suspended ? (
          <div className="mt-7 rounded-3xl border border-amber-200 bg-amber-50 p-5 text-sm font-bold leading-7 text-amber-950">
            Community editing is unavailable while this account is suspended. You may still remove your own eligible Offering from the Journey controls.
          </div>
        ) : moderatorHidden ? (
          <div className="mt-7 rounded-3xl border border-amber-200 bg-amber-50 p-5 text-sm font-bold leading-7 text-amber-950">
            This Offering was hidden by moderation. Member controls cannot edit, restore, or bypass that decision.
          </div>
        ) : offering.status === "rejected" ? (
          <div className="mt-7 rounded-3xl border border-amber-200 bg-amber-50 p-5 text-sm font-bold leading-7 text-amber-950">
            This Offering was not approved. Rejected Offerings cannot be resubmitted from the member editor.
          </div>
        ) : (
          <div className="mt-8">
            <EditOfferingForm offering={offering} />
          </div>
        )}
      </section>
    </main>
  );
}
