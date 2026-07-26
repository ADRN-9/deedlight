import { PendingSubmitButton } from "@/components/ui/pending-submit-button";
import Link from "next/link";
import { notFound } from "next/navigation";
import { AlertTriangle, CheckCircle2, EyeOff, Flag, PencilLine, Save, ShieldCheck, XCircle } from "lucide-react";
import { requireAdmin } from "@/lib/auth/admin";
import { getAdminOffering, getReportsForOffering } from "@/lib/data/offerings";
import type { ReportItem } from "@/lib/types";
import {
  approveOffering,
  dismissReportsForOffering,
  editAndApproveOffering,
  editOfferingContent,
  hideOffering,
  rejectOffering,
  requestOfferingEdit,
  resolveReportsForOffering
} from "./actions";

export const dynamic = "force-dynamic";

const offeringTypeOptions = [
  ["good_deed", "Good Deed"],
  ["goodness_invitation", "Goodness Invitation"],
  ["gratitude", "Gratitude"],
  ["beauty_reminder", "Beauty Reminder"],
  ["quiet_goodness", "Quiet Goodness"],
  ["community_need", "Community Need"]
] as const;

export default async function AdminOfferingDetailPage({
  params,
  searchParams
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ updated?: string; error?: string }>;
}) {
  const { id } = await params;
  const notices = await searchParams;
  await requireAdmin(`/admin/offerings/${id}`);
  const offering = await getAdminOffering(id);

  if (!offering) notFound();

  const reports = await getReportsForOffering(id);
  const openReports = reports.filter((report) => report.status === "open" || report.status === "reviewing");
  const author = offering.is_anonymous ? "Anonymous publicly" : offering.author_name || "Deedlight member";

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
      <div className="mb-8 flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Admin · Quality & Moderation</p>
          <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">Review with dignity.</h1>
          <p className="mt-3 max-w-2xl leading-8 text-[#7C715F]">Edit gently, approve carefully, and protect people’s dignity before content spreads.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Link href="/admin/reports" className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-5 py-3 text-sm font-extrabold text-[#26231F]">
            Reports
          </Link>
          <Link href="/admin/offerings" className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-5 py-3 text-sm font-extrabold text-[#26231F]">
            Back to queue
          </Link>
        </div>
      </div>

      {notices.updated ? (
        <div className="mb-6 rounded-3xl border border-[rgba(217,164,65,0.25)] bg-[#FFF4DC] p-5 font-bold text-[#5F5548]">
          Updated: <span className="capitalize">{notices.updated.replace(/_/g, " ")}</span>.
          {offering.status === "approved" ? (
            <Link href={`/offerings/${offering.id}`} className="ml-2 underline">View public Offering</Link>
          ) : null}
        </div>
      ) : null}

      {notices.error ? (
        <div className="mb-6 rounded-3xl bg-[#FFF0EC] p-5 font-bold text-[#8D381D]">{notices.error}</div>
      ) : null}

      <div className="grid gap-6 lg:grid-cols-[1.15fr_0.85fr]">
        <div className="space-y-6">
          <article className="deed-card overflow-hidden">
            {offering.media_url ? (
              <div className="h-72 bg-cover bg-center" style={{ backgroundImage: `url(${offering.media_url})` }} />
            ) : (
              <div className="h-64 bg-[radial-gradient(circle_at_30%_15%,rgba(244,199,107,0.55),transparent_34%),linear-gradient(135deg,#FFF4DC,#F8EFE0)]" />
            )}
            <div className="p-6 sm:p-8">
              <div className="mb-4 flex flex-wrap gap-2">
                <span className="rounded-full bg-[#FFF4DC] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">{offering.status.replace("_", " ")}</span>
                <span className="rounded-full bg-[#FFF8EA] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">{formatOfferingType(offering.offering_type)}</span>
                {offering.open_report_count ? (
                  <span className="rounded-full bg-[#FFF0EC] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D381D]">
                    {offering.open_report_count} open report{offering.open_report_count === 1 ? "" : "s"}
                  </span>
                ) : null}
              </div>
              <p className="text-sm font-extrabold text-[#26231F]">Author: {author}</p>
              <p className="mt-1 text-xs font-bold text-[#7C715F]">Internal user id: {offering.user_id}</p>
              <h2 className="mt-3 font-[var(--font-heading)] text-4xl font-semibold leading-tight">{offering.title}</h2>
              <p className="mt-5 whitespace-pre-line leading-8 text-[#5F5548]">{offering.body}</p>
              {offering.takeaway ? (
                <div className="mt-6 rounded-3xl border border-[rgba(217,164,65,0.20)] bg-[#FFF8EA] p-5">
                  <p className="text-xs font-extrabold uppercase tracking-[0.18em] text-[#8D681D]">What others can take from this</p>
                  <p className="mt-2 font-bold leading-7 text-[#5F5548]">{offering.takeaway}</p>
                </div>
              ) : null}
              {offering.moderation_note ? (
                <div className="mt-6 rounded-3xl bg-[#FFF4DC] p-5">
                  <p className="text-xs font-extrabold uppercase tracking-[0.18em] text-[#8D681D]">Moderation note</p>
                  <p className="mt-2 font-semibold leading-7 text-[#5F5548]">{offering.moderation_note}</p>
                </div>
              ) : null}
            </div>
          </article>

          <div className="deed-card p-6">
            <div className="mb-5 flex items-center gap-3">
              <PencilLine className="h-5 w-5 text-[#8D681D]" />
              <h2 className="font-[var(--font-heading)] text-3xl font-semibold">Edit before or after approval</h2>
            </div>
            <form action={editOfferingContent} className="space-y-4">
              <input type="hidden" name="id" value={offering.id} />
              <div>
                <label className="text-sm font-extrabold text-[#26231F]" htmlFor="offering_type">Offering type</label>
                <select id="offering_type" name="offering_type" defaultValue={offering.offering_type} className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 font-semibold outline-none focus:border-[#D9A441]">
                  {offeringTypeOptions.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
                </select>
              </div>
              <div>
                <label className="text-sm font-extrabold text-[#26231F]" htmlFor="title">Title</label>
                <input id="title" name="title" defaultValue={offering.title} className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 font-semibold outline-none focus:border-[#D9A441]" />
              </div>
              <div>
                <label className="text-sm font-extrabold text-[#26231F]" htmlFor="body">Story / invitation</label>
                <textarea id="body" name="body" defaultValue={offering.body} className="mt-2 min-h-40 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]" />
              </div>
              <div>
                <label className="text-sm font-extrabold text-[#26231F]" htmlFor="takeaway">Small deed others can try</label>
                <textarea id="takeaway" name="takeaway" defaultValue={offering.takeaway || ""} className="mt-2 min-h-24 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]" />
              </div>
              <div className="grid gap-4 sm:grid-cols-2">
                <div>
                  <label className="text-sm font-extrabold text-[#26231F]" htmlFor="media_url">Media URL</label>
                  <input id="media_url" name="media_url" defaultValue={offering.media_url || ""} className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]" />
                </div>
                <div>
                  <label className="text-sm font-extrabold text-[#26231F]" htmlFor="media_type">Media type</label>
                  <input id="media_type" name="media_type" defaultValue={offering.media_type || ""} placeholder="image / video" className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]" />
                </div>
              </div>
              <div>
                <label className="text-sm font-extrabold text-[#26231F]" htmlFor="location_label">Location label</label>
                <input id="location_label" name="location_label" defaultValue={offering.location_label || ""} className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]" />
              </div>
              <div className="flex flex-wrap gap-4 rounded-3xl bg-[#FFF8EA] p-4">
                <label className="flex items-center gap-2 text-sm font-extrabold text-[#5F5548]"><input type="checkbox" name="is_anonymous" defaultChecked={offering.is_anonymous} /> Keep author anonymous publicly</label>
                <label className="flex items-center gap-2 text-sm font-extrabold text-[#5F5548]"><input type="checkbox" name="allow_reflections" defaultChecked={offering.allow_reflections ?? true} /> Allow reflections</label>
              </div>
              <div className="rounded-3xl border border-[rgba(217,164,65,0.22)] bg-[#FFF8EA] p-4">
                <p className="text-sm font-bold leading-6 text-[#5F5548]">
                  Changes above are not applied until you press one of these buttons. Use “Save edits and publish” when you corrected a typo and want the public Offering updated immediately.
                </p>
                <div className="mt-4 flex flex-wrap gap-3">
                  <button className="focus-ring inline-flex items-center gap-2 rounded-full border border-[rgba(217,164,65,0.35)] bg-white px-5 py-3 font-extrabold text-[#26231F]" type="submit">
                    <Save className="h-4 w-4" /> Save edits only
                  </button>
                  <button formAction={editAndApproveOffering} className="focus-ring inline-flex items-center gap-2 rounded-full bg-[#D9A441] px-5 py-3 font-extrabold text-[#26231F]" type="submit">
                    <CheckCircle2 className="h-4 w-4" /> {offering.status === "approved" ? "Save edits and keep public" : "Save edits and publish"}
                  </button>
                </div>
              </div>
            </form>
          </div>
        </div>

        <aside className="space-y-6">
          <div className="deed-card p-6">
            <div className="flex items-center gap-3">
              <ShieldCheck className="h-6 w-6 text-[#8D681D]" />
              <h2 className="font-[var(--font-heading)] text-2xl font-semibold">Review checklist</h2>
            </div>
            <ul className="mt-5 space-y-3 text-sm font-semibold leading-6 text-[#5F5548]">
              {[
                "Does it protect dignity?",
                "Does it avoid humiliating people?",
                "Does it avoid exposing vulnerable people?",
                "Does it avoid hate or prejudice?",
                "Does it avoid fake charity or fundraising risk?",
                "Does it inspire goodness?",
                "Is the image safe and appropriate?"
              ].map((item) => (
                <li key={item} className="flex gap-2"><CheckCircle2 className="mt-0.5 h-4 w-4 text-[#6F816A]" /> {item}</li>
              ))}
            </ul>
          </div>

          <div className="deed-card p-6">
            <h2 className="font-[var(--font-heading)] text-2xl font-semibold">Decision</h2>
            <p className="mt-2 text-sm leading-6 text-[#7C715F]">
              These actions use the currently saved Offering. If you changed text in the editor, press “Save edits and publish” in the editor first.
            </p>
            <div className="mt-5 grid gap-3">
              <form action={approveOffering}>
                <input type="hidden" name="id" value={offering.id} />
                <button className="focus-ring flex w-full items-center justify-center gap-2 rounded-full bg-[#D9A441] px-5 py-3 font-extrabold text-[#26231F]" type="submit">
                  <CheckCircle2 className="h-4 w-4" /> Approve saved version
                </button>
              </form>

              <form action={requestOfferingEdit} className="rounded-3xl border border-[rgba(217,164,65,0.20)] bg-white p-3">
                <input type="hidden" name="id" value={offering.id} />
                <textarea name="moderation_note" className="min-h-20 w-full rounded-2xl border border-[rgba(217,164,65,0.20)] px-3 py-2 text-sm outline-none focus:border-[#D9A441]" placeholder="Edit request note…" />
                <button className="focus-ring mt-2 flex w-full items-center justify-center gap-2 rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-5 py-3 font-extrabold text-[#26231F]" type="submit">
                  <PencilLine className="h-4 w-4" /> Request edit
                </button>
              </form>

              <form action={rejectOffering} className="rounded-3xl border border-[#E7B7A5] bg-[#FFF0EC] p-3">
                <input type="hidden" name="id" value={offering.id} />
                <textarea name="moderation_note" className="min-h-20 w-full rounded-2xl border border-[#E7B7A5] bg-white px-3 py-2 text-sm outline-none focus:border-[#D9A441]" placeholder="Reason for rejection…" />
                <button className="focus-ring mt-2 flex w-full items-center justify-center gap-2 rounded-full border border-[#E7B7A5] bg-[#FFF0EC] px-5 py-3 font-extrabold text-[#8D381D]" type="submit">
                  <XCircle className="h-4 w-4" /> Reject
                </button>
              </form>

              <form action={hideOffering} className="rounded-3xl border border-[rgba(38,35,31,0.16)] bg-white p-3">
                <input type="hidden" name="id" value={offering.id} />
                <textarea name="moderation_note" className="min-h-20 w-full rounded-2xl border border-[rgba(38,35,31,0.12)] px-3 py-2 text-sm outline-none focus:border-[#D9A441]" placeholder="Reason for hiding…" />
                <button className="focus-ring mt-2 flex w-full items-center justify-center gap-2 rounded-full bg-[#26231F] px-5 py-3 font-extrabold text-white shadow-lg" type="submit">
                  <EyeOff className="h-4 w-4" /> Hide saved Offering from public
                </button>
                <p className="mt-2 text-xs font-semibold leading-5 text-[#7C715F]">
                  This changes the status to hidden and removes it from /offerings and /rising.
                </p>
              </form>
            </div>
          </div>

          <ReportsPanel offeringId={offering.id} reports={reports} openReportsCount={openReports.length} />
        </aside>
      </div>
    </section>
  );
}

function ReportsPanel({ offeringId, reports, openReportsCount }: { offeringId: string; reports: ReportItem[]; openReportsCount: number }) {
  return (
    <div className="deed-card p-6">
      <div className="flex items-center gap-3">
        <Flag className="h-6 w-6 text-[#8D681D]" />
        <h2 className="font-[var(--font-heading)] text-2xl font-semibold">Reports</h2>
      </div>
      <p className="mt-2 text-sm font-semibold leading-6 text-[#7C715F]">{openReportsCount} open report{openReportsCount === 1 ? "" : "s"} for this Offering.</p>

      {reports.length === 0 ? (
        <p className="mt-5 rounded-3xl bg-[#FFF8EA] p-4 text-sm font-semibold text-[#5F5548]">No reports yet.</p>
      ) : (
        <div className="mt-5 space-y-3">
          {reports.map((report) => (
            <div key={report.id} className="rounded-3xl border border-[rgba(217,164,65,0.20)] bg-white p-4">
              <div className="flex flex-wrap items-center gap-2">
                <span className="rounded-full bg-[#FFF4DC] px-3 py-1 text-[11px] font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">{formatReason(report.reason)}</span>
                <span className="rounded-full bg-[#F0EEE8] px-3 py-1 text-[11px] font-extrabold uppercase tracking-[0.14em] text-[#5F5548]">{report.status}</span>
              </div>
              <p className="mt-3 text-sm font-bold text-[#26231F]">Reporter: {report.reporter_name || "Deedlight member"}</p>
              {report.details ? <p className="mt-2 text-sm leading-6 text-[#5F5548]">{report.details}</p> : null}
              {report.admin_note ? <p className="mt-2 text-xs font-semibold leading-5 text-[#7C715F]">Admin note: {report.admin_note}</p> : null}
            </div>
          ))}
        </div>
      )}

      {openReportsCount > 0 ? (
        <div className="mt-5 grid gap-3">
          <form action={resolveReportsForOffering}>
            <input type="hidden" name="id" value={offeringId} />
            <input type="hidden" name="moderation_note" value="Resolved during Offering review." />
            <button className="focus-ring w-full rounded-full bg-[#D9A441] px-5 py-3 text-sm font-extrabold text-[#26231F]" type="submit">Mark reports resolved</button>
          </form>
          <form action={dismissReportsForOffering}>
            <input type="hidden" name="id" value={offeringId} />
            <input type="hidden" name="moderation_note" value="Dismissed after review." />
            <button className="focus-ring w-full rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-5 py-3 text-sm font-extrabold text-[#26231F]" type="submit">Dismiss reports</button>
          </form>
        </div>
      ) : null}
    </div>
  );
}

function formatOfferingType(value: string) {
  return value
    .split("_")
    .map((word) => word[0]?.toUpperCase() + word.slice(1))
    .join(" ");
}

function formatReason(value: string) {
  return value
    .split("_")
    .map((word) => word[0]?.toUpperCase() + word.slice(1))
    .join(" ");
}
