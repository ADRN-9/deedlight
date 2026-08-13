import Link from "next/link";
import { redirect } from "next/navigation";
import { PendingActionButton } from "@/components/growth/pending-action-button";
import { ShareButton } from "@/components/share-button";
import { requireSignedIn } from "@/lib/auth/admin";
import { getMyInvitationLinks } from "@/lib/data/invitations";
import {
  createInvitationLinkAction,
  revokeInvitationLinkAction,
} from "./actions";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type SearchParams = Promise<
  Record<string, string | string[] | undefined>
>;

function firstValue(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

export default async function InvitePage({
  searchParams,
}: {
  searchParams?: SearchParams;
}) {
  const params = searchParams ? await searchParams : {};
  const { supabase, user } = await requireSignedIn("/invite");

  const [{ data: profile, error: profileError }, links] =
    await Promise.all([
      supabase
        .from("profiles")
        .select("is_suspended")
        .eq("user_id", user.id)
        .maybeSingle(),
      getMyInvitationLinks(user.id),
    ]);

  if (profileError) {
    redirect(
      "/journey?error=" +
        encodeURIComponent(
          "Invitation access could not be verified.",
        ),
    );
  }

  const now = Date.now();
  const activeLink =
    links.find(
      (item) =>
        !item.revoked_at &&
        new Date(item.expires_at).getTime() > now,
    ) || null;

  const siteUrl = (
    process.env.NEXT_PUBLIC_SITE_URL ||
    "http://localhost:3000"
  ).replace(/\/$/, "");

  const inviteUrl = activeLink
    ? `${siteUrl}/signup?invite=${encodeURIComponent(
        activeLink.code,
      )}`
    : null;

  const errorMessage = firstValue(params.error);
  const totalAccepted = links.reduce(
    (sum, item) => sum + Number(item.accepted_count || 0),
    0,
  );

  return (
    <section className="mx-auto max-w-4xl px-4 py-12 sm:px-6 sm:py-16">
      <div className="deed-card p-6 sm:p-10">
        <p className="text-xs font-extrabold uppercase tracking-[0.3em] text-[#8D681D]">
          Invitations
        </p>
        <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold leading-tight">
          Pass the light personally.
        </h1>
        <p className="mt-4 max-w-2xl leading-8 text-[#5F5548]">
          Create one private invitation link and share it
          yourself. Deedlight does not send invitation email in
          this foundation release, and the link never publicly
          identifies you.
        </p>

        {params.created === "1" ? (
          <div className="mt-6 rounded-3xl border border-emerald-100 bg-emerald-50 p-5 text-sm font-extrabold text-emerald-900">
            Your invitation link is ready to share.
          </div>
        ) : null}

        {params.revoked === "1" ? (
          <div className="mt-6 rounded-3xl border border-emerald-100 bg-emerald-50 p-5 text-sm font-extrabold text-emerald-900">
            That invitation link has been revoked.
          </div>
        ) : null}

        {errorMessage ? (
          <div className="mt-6 rounded-3xl border border-amber-200 bg-[#FFF4DC] p-5 text-sm font-extrabold text-[#8D381D]">
            {errorMessage}
          </div>
        ) : null}

        {activeLink && inviteUrl ? (
          <div className="mt-8 rounded-3xl border border-[rgba(217,164,65,0.22)] bg-[#FFF8EA] p-6">
            <p className="text-xs font-extrabold uppercase tracking-[0.18em] text-[#8D681D]">
              Your active link
            </p>

            <div className="mt-3 break-all rounded-2xl bg-white p-4 font-mono text-sm text-[#4D4338]">
              {inviteUrl}
            </div>

            <p className="mt-4 text-sm leading-7 text-[#6B6054]">
              Accepted joins through your private links:{" "}
              <strong>{totalAccepted}</strong>. This number is
              visible only to you and is never used for a public
              member ranking.
            </p>

            <p className="mt-2 text-sm leading-7 text-[#6B6054]">
              This link expires{" "}
              {new Date(activeLink.expires_at).toLocaleDateString(
                "en-US",
                {
                  month: "long",
                  day: "numeric",
                  year: "numeric",
                },
              )}
              .
            </p>

            <div className="mt-5 flex flex-wrap gap-3">
              <ShareButton
                title="Join me on Deedlight"
                text="A daily space for goodness, beauty, and better deeds."
                url={inviteUrl}
                label="Share invitation"
              />

              <form action={revokeInvitationLinkAction}>
                <input
                  type="hidden"
                  name="invitation_id"
                  value={activeLink.id}
                />
                <PendingActionButton
                  idleLabel="Revoke link"
                  pendingLabel="Revoking…"
                  className="focus-ring rounded-full border border-[rgba(217,164,65,0.34)] bg-white px-5 py-3 text-sm font-extrabold text-[#3F352B] disabled:cursor-not-allowed disabled:opacity-60"
                />
              </form>
            </div>
          </div>
        ) : (
          <div className="mt-8 rounded-3xl border border-[rgba(217,164,65,0.22)] bg-[#FFF8EA] p-6">
            <h2 className="font-[var(--font-heading)] text-3xl font-semibold">
              Create a private invitation link.
            </h2>
            <p className="mt-3 max-w-2xl text-sm leading-7 text-[#6B6054]">
              One active link can be reused. Revoked links stop
              working immediately, and Deedlight limits repeated
              link creation to reduce abuse.
            </p>

            {profile?.is_suspended ? (
              <p className="mt-5 rounded-2xl bg-white p-4 text-sm font-bold leading-7 text-[#7A4A33]">
                Invitation creation is unavailable while community
                access is suspended.
              </p>
            ) : (
              <form action={createInvitationLinkAction} className="mt-5">
                <PendingActionButton
                  idleLabel="Create invitation link"
                  pendingLabel="Creating link…"
                  className="focus-ring rounded-full bg-[#D9A441] px-6 py-3 text-sm font-extrabold text-[#26231F] shadow-[0_12px_25px_rgba(217,164,65,0.30)] disabled:cursor-not-allowed disabled:opacity-60"
                />
              </form>
            )}
          </div>
        )}

        <div className="mt-8 flex flex-wrap gap-3">
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
            Invitation privacy
          </Link>
        </div>
      </div>
    </section>
  );
}
