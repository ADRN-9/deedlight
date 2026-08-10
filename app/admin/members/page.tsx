import Link from "next/link";
import { ShieldAlert, ShieldCheck, UserRound } from "lucide-react";
import { requireDatabaseAdmin } from "@/lib/auth/admin";
import {
  getAdminMembers,
  type AdminMemberState,
  type AdminMemberSummary,
} from "@/lib/data/members";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const stateOptions: Array<[AdminMemberState, string]> = [
  ["all", "All members"],
  ["active", "Active"],
  ["suspended", "Suspended"],
];

export default async function AdminMembersPage({
  searchParams,
}: {
  searchParams: Promise<{ state?: string }>;
}) {
  await requireDatabaseAdmin("/admin/members");

  const params = await searchParams;
  const state: AdminMemberState =
    params.state === "active" || params.state === "suspended"
      ? params.state
      : "all";

  const members = await getAdminMembers(state);

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
      <div className="mb-8 flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">
            Admin · Members
          </p>
          <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">
            Moderate people with context, not rankings.
          </h1>
          <p className="mt-3 max-w-3xl leading-8 text-[#7C715F]">
            Review public identity, Offering history, report context, and prior
            moderation actions. Private Daily reflections and community
            reflection text are intentionally excluded.
          </p>
        </div>

        <Link
          href="/admin"
          className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-5 py-3 text-center text-sm font-extrabold text-[#26231F]"
        >
          Back to Admin
        </Link>
      </div>

      <div className="mb-7 flex flex-wrap gap-2">
        {stateOptions.map(([value, label]) => (
          <Link
            key={value}
            href={`/admin/members?state=${value}`}
            className={`focus-ring rounded-full px-4 py-2 text-sm font-extrabold ${
              state === value
                ? "bg-[#D9A441] text-[#26231F]"
                : "border border-[rgba(217,164,65,0.25)] bg-white/70 text-[#5F5548]"
            }`}
          >
            {label}
          </Link>
        ))}
      </div>

      {members.length === 0 ? (
        <div className="deed-card p-8 text-center">
          <UserRound className="mx-auto h-9 w-9 text-[#8D681D]" />
          <p className="mt-4 font-[var(--font-heading)] text-3xl font-semibold">
            No members in this view.
          </p>
          <p className="mt-3 text-[#7C715F]">
            Change the filter to review another member state.
          </p>
        </div>
      ) : (
        <div className="grid gap-5">
          {members.map((member) => (
            <MemberRow key={member.member_user_id} member={member} />
          ))}
        </div>
      )}
    </section>
  );
}

function MemberRow({ member }: { member: AdminMemberSummary }) {
  const publicProfileVisible = member.is_public && !member.is_suspended;

  return (
    <article className="deed-card p-5 sm:p-6">
      <div className="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <MemberStatus suspended={member.is_suspended} />
            <span className="rounded-full bg-[#FFF8EA] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">
              {formatRole(member.role)}
            </span>
            {member.is_verified ? (
              <span className="rounded-full bg-[#EFF7ED] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#3F6E39]">
                Verified
              </span>
            ) : null}
            {publicProfileVisible ? (
              <span className="rounded-full bg-[#EEF5FF] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#37618D]">
                Public profile
              </span>
            ) : null}
          </div>

          <h2 className="mt-4 font-[var(--font-heading)] text-3xl font-semibold">
            {member.display_name}
          </h2>
          <p className="mt-1 text-sm font-bold text-[#7C715F]">
            @{member.username} · joined {formatDate(member.member_since)}
          </p>

          <div className="mt-5 grid gap-3 sm:grid-cols-4">
            <Metric value={member.offering_count} label="Offerings" />
            <Metric value={member.approved_offering_count} label="Approved" />
            <Metric value={member.pending_offering_count} label="Pending" />
            <Metric value={member.open_report_count} label="Open reports" />
          </div>

          {member.last_action && member.last_reason ? (
            <div className="mt-5 rounded-2xl bg-[#FFF8EA] p-4 text-sm leading-7 text-[#5F5548]">
              <span className="font-extrabold">
                Last moderation: {member.last_action}
              </span>
              {" — "}
              {member.last_reason}
            </div>
          ) : null}
        </div>

        <div className="flex shrink-0 flex-wrap gap-2">
          <Link
            href={`/admin/members/${member.member_user_id}`}
            className="focus-ring rounded-full bg-[#D9A441] px-5 py-3 text-sm font-extrabold text-[#26231F]"
          >
            Review member
          </Link>
          {publicProfileVisible ? (
            <Link
              href={`/people/${member.username}`}
              className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-5 py-3 text-sm font-extrabold text-[#26231F]"
            >
              Public profile
            </Link>
          ) : null}
        </div>
      </div>
    </article>
  );
}

function MemberStatus({ suspended }: { suspended: boolean }) {
  return suspended ? (
    <span className="inline-flex items-center gap-1.5 rounded-full bg-[#FFF0EC] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D381D]">
      <ShieldAlert className="h-3.5 w-3.5" /> Suspended
    </span>
  ) : (
    <span className="inline-flex items-center gap-1.5 rounded-full bg-[#EFF7ED] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#3F6E39]">
      <ShieldCheck className="h-3.5 w-3.5" /> Active
    </span>
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

function formatRole(value: string) {
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
