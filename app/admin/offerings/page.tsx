import Link from "next/link";
import type { ReactNode } from "react";
import { AlertTriangle, CheckCircle2, Clock, EyeOff, PencilLine, XCircle } from "lucide-react";
import { requireAdmin } from "@/lib/auth/admin";
import { getAdminOfferings } from "@/lib/data/offerings";
import type { AdminOffering } from "@/lib/types";

const statusOptions = [
  ["pending", "Pending review"],
  ["needs_edit", "Needs edit"],
  ["approved", "Approved"],
  ["rejected", "Rejected"],
  ["hidden", "Hidden"],
  ["all", "All"]
] as const;

export default async function AdminOfferingsPage({ searchParams }: { searchParams: Promise<{ status?: string }> }) {
  await requireAdmin("/admin/offerings");
  const params = await searchParams;
  const status = params.status || "pending";
  const offerings = await getAdminOfferings(status, 80);

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
      <div className="mb-8 flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Admin · Offerings Review</p>
          <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">Protect the stream of goodness.</h1>
          <p className="mt-3 max-w-2xl leading-8 text-[#7C715F]">
            Review Offerings before they appear publicly. Approve what inspires goodness and protects dignity.
          </p>
        </div>
        <Link href="/admin" className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-5 py-3 text-sm font-extrabold text-[#26231F]">
          Back to Admin
        </Link>
      </div>

      <div className="mb-7 flex flex-wrap gap-2">
        {statusOptions.map(([value, label]) => (
          <Link
            key={value}
            href={`/admin/offerings?status=${value}`}
            className={`focus-ring rounded-full px-4 py-2 text-sm font-extrabold ${status === value ? "bg-[#D9A441] text-[#26231F]" : "border border-[rgba(217,164,65,0.25)] bg-white/70 text-[#5F5548]"}`}
          >
            {label}
          </Link>
        ))}
      </div>

      {offerings.length === 0 ? (
        <div className="deed-card p-8 text-center">
          <p className="font-[var(--font-heading)] text-3xl font-semibold">No Offerings here yet.</p>
          <p className="mt-3 text-[#7C715F]">When members submit Offerings, they will appear in this review queue.</p>
        </div>
      ) : (
        <div className="grid gap-5">
          {offerings.map((offering) => <AdminOfferingRow key={offering.id} offering={offering} />)}
        </div>
      )}
    </section>
  );
}

function AdminOfferingRow({ offering }: { offering: AdminOffering }) {
  const author = offering.is_anonymous ? "Anonymous Light" : offering.author_name || "Deedlight member";

  return (
    <article className="deed-card p-5 sm:p-6">
      <div className="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
        <div className="min-w-0 flex-1">
          <div className="mb-3 flex flex-wrap items-center gap-2">
            <StatusBadge status={offering.status} />
            <span className="rounded-full bg-[#FFF8EA] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">
              {formatOfferingType(offering.offering_type)}
            </span>
            {offering.open_report_count ? (
              <span className="rounded-full bg-[#FFF0EC] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D381D]">
                {offering.open_report_count} report{offering.open_report_count === 1 ? "" : "s"}
              </span>
            ) : null}
          </div>
          <p className="text-sm font-extrabold text-[#26231F]">{author}</p>
          <h2 className="mt-2 font-[var(--font-heading)] text-3xl font-semibold leading-tight">{offering.title}</h2>
          <p className="mt-3 line-clamp-2 leading-7 text-[#5F5548]">{offering.body}</p>
          {offering.moderation_note ? (
            <p className="mt-4 rounded-2xl bg-[#FFF4DC] p-4 text-sm font-semibold text-[#5F5548]">Note: {offering.moderation_note}</p>
          ) : null}
        </div>
        <div className="flex shrink-0 flex-wrap gap-2">
          <Link href={`/admin/offerings/${offering.id}`} className="focus-ring rounded-full bg-[#D9A441] px-5 py-3 text-sm font-extrabold text-[#26231F]">
            Review
          </Link>
          {offering.status === "approved" ? (
            <Link href={`/offerings/${offering.id}`} className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-5 py-3 text-sm font-extrabold text-[#26231F]">
              Public page
            </Link>
          ) : null}
        </div>
      </div>
    </article>
  );
}

function StatusBadge({ status }: { status: AdminOffering["status"] }) {
  const styles: Record<AdminOffering["status"], string> = {
    draft: "bg-[#F0EEE8] text-[#5F5548]",
    pending: "bg-[#FFF4DC] text-[#8D681D]",
    approved: "bg-[#EFF7ED] text-[#3F6E39]",
    rejected: "bg-[#FFF0EC] text-[#8D381D]",
    needs_edit: "bg-[#EEF5FF] text-[#37618D]",
    hidden: "bg-[#F0EEE8] text-[#5F5548]"
  };
  const icons: Record<AdminOffering["status"], ReactNode> = {
    draft: <PencilLine className="h-3.5 w-3.5" />,
    pending: <Clock className="h-3.5 w-3.5" />,
    approved: <CheckCircle2 className="h-3.5 w-3.5" />,
    rejected: <XCircle className="h-3.5 w-3.5" />,
    needs_edit: <AlertTriangle className="h-3.5 w-3.5" />,
    hidden: <EyeOff className="h-3.5 w-3.5" />
  };

  return (
    <span className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] ${styles[status]}`}>
      {icons[status]} {status.replace("_", " ")}
    </span>
  );
}

function formatOfferingType(value: string) {
  return value
    .split("_")
    .map((word) => word[0]?.toUpperCase() + word.slice(1))
    .join(" ");
}
