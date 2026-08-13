import type { ReactNode } from "react";

export default function PrivacyPage() {
  return (
    <section className="mx-auto max-w-3xl px-4 py-16 sm:px-6">
      <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">
        Product privacy summary
      </p>

      <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">
        Privacy should match the spirit of the deed.
      </h1>

      <p className="mt-6 leading-8 text-[#5F5548]">
        This page explains Deedlight&apos;s current product privacy
        behavior in plain language. It is not a substitute for the
        final legal privacy policy, which must be completed before
        launch.
      </p>

      <div className="mt-10 space-y-8 text-[#5F5548]">
        <PrivacySection title="Private daily activity">
          Daily reflections remain private and are never used as
          public profile content, invitation context, or Weekly
          Goodness content. Daily deed completions, Saved Lights,
          and reminder preferences are also private account data.
        </PrivacySection>

        <PrivacySection title="Account email">
          Your email address is used for account authentication
          through Supabase Auth. Deedlight does not put your email
          address in public profile or Offering projections.
        </PrivacySection>

        <PrivacySection title="Invitation links">
          Invitation links contain an opaque random code, not an
          inviter&apos;s name, username, email address, or public
          user ID. Deedlight privately records which account
          created a link and, after a new account is confirmed,
          whether that invitation was accepted. Invitee identities
          and invitation attribution are not public, and invitation
          counts are not used for a public member ranking.
        </PrivacySection>

        <PrivacySection title="Newsletter consent">
          The Weekly Goodness newsletter preference is optional and
          off by default. Deedlight stores the account ID, consent
          state, and consent timing without duplicating the account
          email into the preference table. You can turn the
          preference off in settings at any time. Newsletter
          delivery is not active yet; no delivery provider is
          included in Sprint 11.3.
        </PrivacySection>

        <PrivacySection title="Anonymous Offerings">
          When an Offering is anonymous, public surfaces are
          designed not to expose its author&apos;s account ID, name,
          or username. Suspended-member attribution is also
          suppressed from public community projections.
        </PrivacySection>
      </div>
    </section>
  );
}

function PrivacySection({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <section className="rounded-3xl border border-[rgba(217,164,65,0.18)] bg-white p-6">
      <h2 className="font-[var(--font-heading)] text-3xl font-semibold text-[#26231F]">
        {title}
      </h2>
      <p className="mt-3 leading-8">{children}</p>
    </section>
  );
}
