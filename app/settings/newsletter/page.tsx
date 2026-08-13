import Link from "next/link";
import { redirect } from "next/navigation";
import { NewsletterSettingsForm } from "@/components/newsletter/newsletter-settings-form";
import { requireSignedIn } from "@/lib/auth/admin";
import { getNewsletterPreference } from "@/lib/data/newsletter";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type SearchParams = Promise<
  Record<string, string | string[] | undefined>
>;

function firstValue(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

export default async function NewsletterSettingsPage({
  searchParams,
}: {
  searchParams?: SearchParams;
}) {
  const params = searchParams ? await searchParams : {};
  const { supabase, user } = await requireSignedIn(
    "/settings/newsletter",
  );

  const [{ data: profile, error: profileError }, preference] =
    await Promise.all([
      supabase
        .from("profiles")
        .select("is_suspended")
        .eq("user_id", user.id)
        .maybeSingle(),
      getNewsletterPreference(user.id),
    ]);

  if (profileError) {
    redirect(
      "/journey?error=" +
        encodeURIComponent(
          "Newsletter settings could not be verified.",
        ),
    );
  }

  const errorMessage = firstValue(params.error);
  const updatedState = firstValue(params.updated);

  return (
    <section className="mx-auto max-w-4xl px-4 py-12 sm:px-6 sm:py-16">
      <div className="deed-card p-6 sm:p-10">
        <p className="text-xs font-extrabold uppercase tracking-[0.3em] text-[#8D681D]">
          Newsletter preference
        </p>

        <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold leading-tight">
          Choose whether Weekly Goodness may reach your inbox.
        </h1>

        <p className="mt-4 max-w-2xl leading-8 text-[#5F5548]">
          This preference is private, optional, and off by
          default. Sprint 11.3 stores consent only; Deedlight does
          not yet have an active newsletter delivery provider.
        </p>

        {updatedState === "enabled" ? (
          <div className="mt-6 rounded-3xl border border-emerald-100 bg-emerald-50 p-5 text-sm font-extrabold text-emerald-900">
            Newsletter consent is on. Delivery is not active yet.
          </div>
        ) : null}

        {updatedState === "disabled" ? (
          <div className="mt-6 rounded-3xl border border-emerald-100 bg-emerald-50 p-5 text-sm font-extrabold text-emerald-900">
            Newsletter preference is off. Your consent has been
            revoked.
          </div>
        ) : null}

        {errorMessage ? (
          <div className="mt-6 rounded-3xl border border-amber-200 bg-[#FFF4DC] p-5 text-sm font-extrabold text-[#8D381D]">
            {errorMessage}
          </div>
        ) : null}

        <NewsletterSettingsForm
          initialEnabled={preference.weekly_enabled}
          isSuspended={profile?.is_suspended === true}
        />

        <div className="mt-7 rounded-3xl border border-[rgba(217,164,65,0.18)] bg-white p-5 text-sm leading-7 text-[#6B6054]">
          <p className="font-extrabold text-[#26231F]">
            Privacy by minimization
          </p>
          <p className="mt-2">
            This preference table does not duplicate your email
            address. Your account email remains private in
            Supabase Auth. A future delivery system must be
            separately implemented and tested before any
            newsletter is sent.
          </p>
        </div>

        <div className="mt-7 flex flex-wrap gap-3">
          <Link
            href="/settings/profile"
            className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-6 py-3 text-sm font-extrabold text-[#26231F]"
          >
            Profile settings
          </Link>

          <Link
            href="/privacy"
            className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-6 py-3 text-sm font-extrabold text-[#26231F]"
          >
            Privacy summary
          </Link>
        </div>
      </div>
    </section>
  );
}
