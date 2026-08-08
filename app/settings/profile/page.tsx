import Link from "next/link";
import { redirect } from "next/navigation";
import { requireSignedIn } from "@/lib/auth/admin";
import { updateProfileAction } from "./actions";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type SearchParams = Promise<
  Record<string, string | string[] | undefined>
>;

function firstValue(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

export default async function ProfileSettingsPage({
  searchParams,
}: {
  searchParams?: SearchParams;
}) {
  const params = searchParams ? await searchParams : {};
  const { supabase, user } = await requireSignedIn("/settings/profile");

  const { data: profile, error } = await supabase
    .from("profiles")
    .select(
      "username,display_name,bio,country,is_public,show_contribution_stats,default_offering_anonymous",
    )
    .eq("user_id", user.id)
    .maybeSingle();

  if (error || !profile) {
    redirect("/journey?error=profile_unavailable");
  }

  const publicUrl = `/people/${profile.username}`;
  const errorMessage = firstValue(params.error);

  return (
    <section className="mx-auto max-w-4xl px-4 py-12 sm:px-6 sm:py-16">
      <div className="deed-card p-6 sm:p-10">
        <p className="text-xs font-extrabold uppercase tracking-[0.3em] text-[#8D681D]">
          Profile settings
        </p>
        <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold leading-tight">
          Choose how your light appears.
        </h1>
        <p className="mt-4 max-w-2xl leading-8 text-[#5F5548]">
          Your public profile is optional. Daily reflections always remain
          private and never appear on member pages.
        </p>

        {params.updated === "1" ? (
          <div className="mt-6 rounded-3xl border border-emerald-100 bg-emerald-50 p-5 text-sm font-extrabold text-emerald-900">
            Your profile settings were saved.
          </div>
        ) : null}

        {errorMessage ? (
          <div className="mt-6 rounded-3xl border border-amber-200 bg-[#FFF4DC] p-5 text-sm font-extrabold text-[#8D381D]">
            {errorMessage}
          </div>
        ) : null}

        <form action={updateProfileAction} className="mt-8 space-y-6">
          <div className="grid gap-5 sm:grid-cols-2">
            <label className="block text-sm font-bold text-[#5F5548]">
              Display name
              <input
                className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]"
                name="display_name"
                type="text"
                required
                minLength={2}
                maxLength={60}
                defaultValue={profile.display_name}
                autoComplete="name"
              />
            </label>

            <label className="block text-sm font-bold text-[#5F5548]">
              Username
              <div className="mt-2 flex rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white focus-within:border-[#D9A441]">
                <span className="px-4 py-3 text-[#8D7C66]">@</span>
                <input
                  className="min-w-0 flex-1 rounded-r-2xl bg-transparent py-3 pr-4 outline-none"
                  name="username"
                  type="text"
                  required
                  minLength={3}
                  maxLength={30}
                  pattern="[a-z0-9][a-z0-9_-]{2,29}"
                  defaultValue={profile.username}
                  autoCapitalize="none"
                  autoCorrect="off"
                />
              </div>
            </label>
          </div>

          <label className="block text-sm font-bold text-[#5F5548]">
            Bio
            <textarea
              className="mt-2 min-h-32 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]"
              name="bio"
              maxLength={280}
              defaultValue={profile.bio ?? ""}
              placeholder="A few gentle words about what goodness means to you."
            />
          </label>

          <label className="block text-sm font-bold text-[#5F5548]">
            Country or region
            <input
              className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]"
              name="country"
              type="text"
              maxLength={80}
              defaultValue={profile.country ?? ""}
            />
          </label>

          <div className="space-y-4 rounded-3xl border border-[rgba(217,164,65,0.22)] bg-[#FFF8EA] p-5">
            <Preference
              name="is_public"
              defaultChecked={profile.is_public}
              title="Make my profile public"
              description="People can visit your profile only after you enable this."
            />
            <Preference
              name="show_contribution_stats"
              defaultChecked={profile.show_contribution_stats}
              title="Show gentle contribution totals"
              description="Shows public, non-anonymous Offering totals without rankings or streaks."
            />
            <Preference
              name="default_offering_anonymous"
              defaultChecked={profile.default_offering_anonymous}
              title="Default new Offerings to anonymous"
              description="You can still change anonymity for each Offering before submitting."
            />
          </div>

          <div className="flex flex-col gap-3 sm:flex-row">
            <button
              className="focus-ring rounded-full bg-[#D9A441] px-7 py-3 text-sm font-extrabold text-[#26231F] shadow-[0_12px_25px_rgba(217,164,65,0.30)]"
              type="submit"
            >
              Save profile
            </button>

            {profile.is_public ? (
              <Link
                className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-7 py-3 text-center text-sm font-extrabold text-[#26231F]"
                href={publicUrl}
              >
                View public profile
              </Link>
            ) : null}
          </div>
        </form>
      </div>
    </section>
  );
}

function Preference({
  name,
  defaultChecked,
  title,
  description,
}: {
  name: string;
  defaultChecked: boolean;
  title: string;
  description: string;
}) {
  return (
    <label className="flex items-start gap-3 rounded-2xl bg-white p-4">
      <input
        className="mt-1 h-4 w-4 accent-[#D9A441]"
        name={name}
        type="checkbox"
        defaultChecked={defaultChecked}
      />
      <span>
        <span className="block font-extrabold text-[#26231F]">
          {title}
        </span>
        <span className="mt-1 block text-sm leading-6 text-[#7C715F]">
          {description}
        </span>
      </span>
    </label>
  );
}
