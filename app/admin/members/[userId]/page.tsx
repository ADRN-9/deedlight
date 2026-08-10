import Link from "next/link";
import { notFound } from "next/navigation";
import {
  AlertTriangle,
  CheckCircle2,
  EyeOff,
  Flag,
  ShieldAlert,
  ShieldCheck,
} from "lucide-react";
import { AdminStatusMessage } from "@/components/admin/admin-status-message";
import { requireDatabaseAdmin } from "@/lib/auth/admin";
import { getAdminMemberContext } from "@/lib/data/members";
import { restoreMember, suspendMember } from "./actions";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export default async function AdminMemberDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ userId: string }>;
  searchParams: Promise<{ updated?: string; error?: string }>;
}) {
  const { userId } = await params;
  const notices = await searchParams;

  await requireDatabaseAdmin(`/admin/members/${userId}`);

  const context = await getAdminMemberContext(userId);

  if (!context) {
    notFound();
  }

  const { profile, offerings, reports, moderation_events: events } = context;
  const publicProfileVisible = profile.is_public && !profile.is_suspended;
  const canModerate = profile.role !== "admin";

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
      <div className="mb-8 flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">
            Admin · Member Review
          </p>
          <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">
            {profile.display_name}
          </h1>
          <p className="mt-2 font-bold text-[#7C715F]">
            @{profile.username} · {formatRole(profile.role)}
          </p>
        </div>

        <div className="flex flex-wrap gap-2">
          {publicProfileVisible ? (
            <Link
              href={`/people/${profile.username}`}
              className="focus-ring rounded-full bg-[#D9A441] px-5 py-3 text-sm font-extrabold text-[#26231F]"
            >
              View public profile
            </Link>
          ) : null}
          <Link
            href="/admin/members"
            className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-5 py-3 text-sm font-extrabold text-[#26231F]"
          >
            Back to Members
          </Link>
        </div>
      </div>

      {notices.updated === "suspended" ? (
        <div className="mb-7">
          <AdminStatusMessage type="warning" title="Member suspended">
            Public profile attribution is now suppressed and community write
            policies block new or resubmitted Offerings, reactions, reports,
            and Offering reflections. Private Daily reflections remain
            member-owned.
          </AdminStatusMessage>
        </div>
      ) : null}

      {notices.updated === "restored" ? (
        <div className="mb-7">
          <AdminStatusMessage type="success" title="Member restored">
            Community write access has been restored. The moderation action
            remains in the audit history below.
          </AdminStatusMessage>
        </div>
      ) : null}

      {notices.error ? (
        <div className="mb-7">
          <AdminStatusMessage type="error" title="Moderation action failed">
            {notices.error}
          </AdminStatusMessage>
        </div>
      ) : null}

      <div className="grid gap-6 lg:grid-cols-[1.4fr_0.8fr]">
        <div className="space-y-6">
          <section className="deed-card p-6">
            <div className="flex flex-wrap items-center gap-2">
              {profile.is_suspended ? (
                <span className="inline-flex items-center gap-1.5 rounded-full bg-[#FFF0EC] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D381D]">
                  <ShieldAlert className="h-3.5 w-3.5" /> Suspended
                </span>
              ) : (
                <span className="inline-flex items-center gap-1.5 rounded-full bg-[#EFF7ED] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#3F6E39]">
                  <ShieldCheck className="h-3.5 w-3.5" /> Active
                </span>
              )}
              <span className="rounded-full bg-[#FFF8EA] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">
                {profile.is_public ? "Profile opted public" : "Private profile"}
              </span>
              {profile.is_verified ? (
                <span className="rounded-full bg-[#EEF5FF] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#37618D]">
                  Verified
                </span>
              ) : null}
            </div>

            <div className="mt-6 grid gap-3 sm:grid-cols-3">
              <Metric value={offerings.length} label="Offerings" />
              <Metric value={reports.length} label="Reports on Offerings" />
              <Metric value={events.length} label="Moderation actions" />
            </div>

            <div className="mt-5 rounded-2xl bg-[#FFF8EA] p-4 text-sm leading-7 text-[#5F5548]">
              Joined {formatDate(profile.member_since)}. This workspace does not
              query Daily reflection records or community reflection text.
            </div>
          </section>

          <section>
            <div className="mb-4 flex items-end justify-between gap-4">
              <div>
                <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">
                  Contribution context
                </p>
                <h2 className="mt-2 font-[var(--font-heading)] text-3xl font-semibold">
                  Offerings
                </h2>
              </div>
              <Link
                href="/admin/offerings"
                className="text-sm font-extrabold text-[#8D681D] underline"
              >
                Offering queue
              </Link>
            </div>

            {offerings.length ? (
              <div className="grid gap-4">
                {offerings.map((offering) => (
                  <article key={offering.id} className="deed-card p-5">
                    <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                      <div className="min-w-0">
                        <div className="flex flex-wrap gap-2">
                          <OfferingStatus status={offering.status} />
                          {offering.is_anonymous ? (
                            <span className="rounded-full bg-[#F0EEE8] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#5F5548]">
                              Anonymous publicly
                            </span>
                          ) : null}
                          {offering.open_report_count > 0 ? (
                            <span className="inline-flex items-center gap-1 rounded-full bg-[#FFF0EC] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D381D]">
                              <Flag className="h-3.5 w-3.5" />
                              {offering.open_report_count} open
                            </span>
                          ) : null}
                        </div>
                        <h3 className="mt-3 font-[var(--font-heading)] text-2xl font-semibold">
                          {offering.title}
                        </h3>
                        {offering.moderation_note ? (
                          <p className="mt-3 rounded-2xl bg-[#FFF8EA] p-4 text-sm leading-7 text-[#5F5548]">
                            Moderation note: {offering.moderation_note}
                          </p>
                        ) : null}
                      </div>
                      <Link
                        href={`/admin/offerings/${offering.id}`}
                        className="focus-ring shrink-0 rounded-full bg-[#D9A441] px-4 py-2 text-center text-sm font-extrabold text-[#26231F]"
                      >
                        Review
                      </Link>
                    </div>
                  </article>
                ))}
              </div>
            ) : (
              <div className="deed-card p-6 text-[#7C715F]">
                No Offerings from this member.
              </div>
            )}
          </section>

          <section>
            <div className="mb-4">
              <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">
                Safety context
              </p>
              <h2 className="mt-2 font-[var(--font-heading)] text-3xl font-semibold">
                Reports on this member’s Offerings
              </h2>
            </div>

            {reports.length ? (
              <div className="grid gap-4">
                {reports.map((report) => (
                  <article key={report.id} className="deed-card p-5">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="rounded-full bg-[#FFF0EC] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D381D]">
                        {formatLabel(report.reason)}
                      </span>
                      <span className="rounded-full bg-[#FFF8EA] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">
                        {formatLabel(report.status)}
                      </span>
                    </div>
                    <h3 className="mt-3 text-lg font-extrabold text-[#26231F]">
                      {report.offering_title}
                    </h3>
                    {report.details ? (
                      <p className="mt-3 text-sm leading-7 text-[#5F5548]">
                        Reporter note: {report.details}
                      </p>
                    ) : null}
                    {report.admin_note ? (
                      <p className="mt-2 text-sm leading-7 text-[#7C715F]">
                        Admin note: {report.admin_note}
                      </p>
                    ) : null}
                    <Link
                      href={`/admin/offerings/${report.offering_id}`}
                      className="mt-4 inline-flex text-sm font-extrabold text-[#8D681D] underline"
                    >
                      Review Offering
                    </Link>
                  </article>
                ))}
              </div>
            ) : (
              <div className="deed-card p-6 text-[#7C715F]">
                No reports are attached to this member’s Offerings.
              </div>
            )}
          </section>
        </div>

        <aside className="space-y-6">
          <section className="deed-card p-6">
            <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">
              Member moderation
            </p>
            <h2 className="mt-2 font-[var(--font-heading)] text-3xl font-semibold">
              {profile.is_suspended ? "Restore access" : "Suspend community access"}
            </h2>

            {!canModerate ? (
              <div className="mt-5 rounded-2xl bg-[#FFF8EA] p-4 text-sm leading-7 text-[#5F5548]">
                Admin accounts are intentionally excluded from the member
                suspension tool to reduce lockout and account-takeover risk.
              </div>
            ) : profile.is_suspended ? (
              <form action={restoreMember} className="mt-5">
                <input type="hidden" name="user_id" value={profile.user_id} />
                <label className="text-sm font-extrabold text-[#26231F]">
                  Restore reason
                  <textarea
                    name="reason"
                    required
                    minLength={8}
                    maxLength={500}
                    className="mt-2 min-h-28 w-full rounded-2xl border border-[rgba(217,164,65,0.30)] bg-white p-3 text-sm leading-7 outline-none focus:border-[#D9A441]"
                    placeholder="Why is community access safe to restore now?"
                  />
                </label>
                <button
                  type="submit"
                  className="focus-ring mt-4 w-full rounded-full bg-[#D9A441] px-5 py-3 text-sm font-extrabold text-[#26231F]"
                >
                  Restore member
                </button>
              </form>
            ) : (
              <form action={suspendMember} className="mt-5">
                <input type="hidden" name="user_id" value={profile.user_id} />
                <label className="text-sm font-extrabold text-[#26231F]">
                  Suspension reason
                  <textarea
                    name="reason"
                    required
                    minLength={8}
                    maxLength={500}
                    className="mt-2 min-h-28 w-full rounded-2xl border border-[#E7B7A5] bg-white p-3 text-sm leading-7 outline-none focus:border-[#D9A441]"
                    placeholder="State the concrete moderation reason. This is stored in the audit history."
                  />
                </label>
                <div className="mt-3 rounded-2xl bg-[#FFF0EC] p-4 text-xs leading-6 text-[#8D381D]">
                  Suspension hides public profile attribution and blocks
                  community writes. It does not delete content and does not
                  remove access to private Daily reflections.
                </div>
                <button
                  type="submit"
                  className="focus-ring mt-4 w-full rounded-full bg-[#26231F] px-5 py-3 text-sm font-extrabold text-white"
                >
                  Suspend member
                </button>
              </form>
            )}
          </section>

          <section className="deed-card p-6">
            <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">
              Audit history
            </p>
            <h2 className="mt-2 font-[var(--font-heading)] text-3xl font-semibold">
              Suspension record
            </h2>

            {events.length ? (
              <div className="mt-5 space-y-4">
                {events.map((event) => (
                  <div
                    key={event.id}
                    className="rounded-2xl border border-[rgba(217,164,65,0.20)] bg-[#FFF8EA] p-4"
                  >
                    <div className="flex items-center gap-2">
                      {event.action === "suspended" ? (
                        <AlertTriangle className="h-4 w-4 text-[#8D381D]" />
                      ) : (
                        <CheckCircle2 className="h-4 w-4 text-[#3F6E39]" />
                      )}
                      <p className="font-extrabold text-[#26231F]">
                        {formatLabel(event.action)}
                      </p>
                    </div>
                    <p className="mt-2 text-sm leading-7 text-[#5F5548]">
                      {event.reason}
                    </p>
                    <p className="mt-2 text-xs font-bold text-[#7C715F]">
                      {event.actor_name} · {formatDateTime(event.created_at)}
                    </p>
                  </div>
                ))}
              </div>
            ) : (
              <p className="mt-5 text-sm leading-7 text-[#7C715F]">
                No suspension or restore actions have been recorded.
              </p>
            )}
          </section>
        </aside>
      </div>
    </section>
  );
}

function Metric({ value, label }: { value: number; label: string }) {
  return (
    <div className="rounded-2xl bg-[#FFF8EA] p-4">
      <p className="text-2xl font-black text-[#26231F]">{value}</p>
      <p className="mt-1 text-xs font-extrabold uppercase tracking-[0.16em] text-[#8D681D]">
        {label}
      </p>
    </div>
  );
}

function OfferingStatus({ status }: { status: string }) {
  const hidden = status === "hidden" || status === "rejected";

  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] ${
        hidden
          ? "bg-[#F0EEE8] text-[#5F5548]"
          : status === "approved"
            ? "bg-[#EFF7ED] text-[#3F6E39]"
            : "bg-[#FFF4DC] text-[#8D681D]"
      }`}
    >
      {hidden ? <EyeOff className="h-3.5 w-3.5" /> : null}
      {formatLabel(status)}
    </span>
  );
}

function formatRole(value: string) {
  return formatLabel(value);
}

function formatLabel(value: string) {
  return value
    .split("_")
    .map((word) => word[0]?.toUpperCase() + word.slice(1))
    .join(" ");
}

function formatDate(value: string) {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "unknown date";
  }

  return new Intl.DateTimeFormat("en", {
    year: "numeric",
    month: "short",
    day: "numeric",
  }).format(date);
}

function formatDateTime(value: string) {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "unknown time";
  }

  return new Intl.DateTimeFormat("en", {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}
