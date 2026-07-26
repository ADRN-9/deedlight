import Link from "next/link";
import { Flag } from "lucide-react";
import { requireAdmin } from "@/lib/auth/admin";
import { getAdminReports } from "@/lib/data/offerings";
import type { ReportItem } from "@/lib/types";

const statusOptions = [
  ["open", "Open"],
  ["reviewing", "Reviewing"],
  ["resolved", "Resolved"],
  ["dismissed", "Dismissed"],
  ["all", "All"]
] as const;

export default async function AdminReportsPage({ searchParams }: { searchParams: Promise<{ status?: string }> }) {
  await requireAdmin("/admin/reports");
  const params = await searchParams;
  const status = params.status || "open";
  const reports = await getAdminReports(status, 100);

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
      <div className="mb-8 flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Admin · Reports</p>
          <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">Dignity report queue.</h1>
          <p className="mt-3 max-w-2xl leading-8 text-[#7C715F]">Review reports from members and decide whether to edit, hide, dismiss, or resolve.</p>
        </div>
        <Link href="/admin/offerings" className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-5 py-3 text-sm font-extrabold text-[#26231F]">
          Offerings review
        </Link>
      </div>

      <div className="mb-7 flex flex-wrap gap-2">
        {statusOptions.map(([value, label]) => (
          <Link
            key={value}
            href={`/admin/reports?status=${value}`}
            className={`focus-ring rounded-full px-4 py-2 text-sm font-extrabold ${status === value ? "bg-[#D9A441] text-[#26231F]" : "border border-[rgba(217,164,65,0.25)] bg-white/70 text-[#5F5548]"}`}
          >
            {label}
          </Link>
        ))}
      </div>

      {reports.length === 0 ? (
        <div className="deed-card p-8 text-center">
          <p className="font-[var(--font-heading)] text-3xl font-semibold">No reports in this queue.</p>
          <p className="mt-3 text-[#7C715F]">When members report a concern, it will appear here.</p>
        </div>
      ) : (
        <div className="grid gap-5">
          {reports.map((report) => <ReportRow key={report.id} report={report} />)}
        </div>
      )}
    </section>
  );
}

function ReportRow({ report }: { report: ReportItem }) {
  const offering = report.offering;
  return (
    <article className="deed-card p-5 sm:p-6">
      <div className="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
        <div className="min-w-0 flex-1">
          <div className="mb-3 flex flex-wrap items-center gap-2">
            <span className="inline-flex items-center gap-1 rounded-full bg-[#FFF0EC] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D381D]"><Flag className="h-3.5 w-3.5" /> {formatReason(report.reason)}</span>
            <span className="rounded-full bg-[#F0EEE8] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#5F5548]">{report.status}</span>
          </div>
          <p className="text-sm font-extrabold text-[#26231F]">Reported by: {report.reporter_name || "Deedlight member"}</p>
          <h2 className="mt-2 font-[var(--font-heading)] text-3xl font-semibold leading-tight">{offering?.title || "Offering not found"}</h2>
          {offering?.body ? <p className="mt-3 line-clamp-2 leading-7 text-[#5F5548]">{offering.body}</p> : null}
          {report.details ? <p className="mt-4 rounded-2xl bg-[#FFF4DC] p-4 text-sm font-semibold text-[#5F5548]">Reporter note: {report.details}</p> : null}
          {report.admin_note ? <p className="mt-3 text-sm font-semibold text-[#7C715F]">Admin note: {report.admin_note}</p> : null}
        </div>
        <div className="flex shrink-0 flex-wrap gap-2">
          {report.offering_id ? (
            <Link href={`/admin/offerings/${report.offering_id}`} className="focus-ring rounded-full bg-[#D9A441] px-5 py-3 text-sm font-extrabold text-[#26231F]">
              Review Offering
            </Link>
          ) : null}
        </div>
      </div>
    </article>
  );
}

function formatReason(value: string) {
  return value
    .split("_")
    .map((word) => word[0]?.toUpperCase() + word.slice(1))
    .join(" ");
}
