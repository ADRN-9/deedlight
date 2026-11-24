import Link from "next/link";
import { notFound } from "next/navigation";
import { AdminStatusMessage } from "@/components/admin/admin-status-message";
import { requireDatabaseAdmin } from "@/lib/auth/admin";
import { resolveProviderIntegrityConflict } from "../actions";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type IntegrityCase = {
  conflict_id: number | string;
  recipient_email: string;
  anomaly_type: string;
  state: "open" | "resolved";
  first_detected_at: string;
  last_detected_at: string;
  evidence_count: number;
  resolved_at: string | null;
  resolved_by: string | null;
  resolution_note: string | null;
};

type IntegrityEvidence = {
  evidence_id: number | string;
  observed_at: string;
  recipient_email: string;
  event_id: string;
  related_event_id: string | null;
  event_type: string;
  provider_email_id: string | null;
  provider_suppression_id: string | null;
  provider_created_at: string | null;
  bounce_type: string | null;
  failure_class: string | null;
  suppression_reason: string | null;
  suppression_origin: string | null;
  suppression_source_id: string | null;
  suppression_created_at: string | null;
  payload_fingerprint: string | null;
  stored_event_id: string;
  stored_recipient_email: string;
  evidence_source: string;
};

type IntegrityHistory = {
  history_id: number | string;
  action: "resolved" | "reopened";
  actor_id: string | null;
  note: string;
  evidence_id: number | string | null;
  created_at: string;
};

const anomalyLabels: Record<string, string> = {
  duplicate_event_id_conflict: "Conflicting event identifier",
  contradictory_terminal_outcome: "Contradictory delivery outcome",
  suppression_event_timestamp_conflict: "Conflicting suppression timeline",
  provider_email_recipient_conflict: "Provider email recipient mismatch",
  provider_suppression_recipient_conflict: "Provider suppression recipient mismatch",
};

function formatDate(value: string | null) {
  if (!value) return "Not recorded";
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? "Unknown time"
    : new Intl.DateTimeFormat("en", {
        dateStyle: "medium",
        timeStyle: "short",
        timeZone: "UTC",
      }).format(date) + " UTC";
}

function Field({ label, value }: { label: string; value: string | null }) {
  if (!value) return null;
  return (
    <div className="min-w-0 rounded-2xl bg-[#FFF8EA] p-3">
      <p className="text-[11px] font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">
        {label}
      </p>
      <p className="mt-1 break-all text-sm leading-6 text-[#3F382F]">{value}</p>
    </div>
  );
}

export default async function AdminProviderIntegrityDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ conflictId: string }>;
  searchParams: Promise<{ updated?: string; error?: string }>;
}) {
  const { conflictId } = await params;
  const notices = await searchParams;

  if (!/^[1-9]\d{0,18}$/.test(conflictId) ||
      (conflictId.length === 19 && conflictId > "9223372036854775807")) {
    notFound();
  }

  const { supabase } = await requireDatabaseAdmin(
    `/admin/provider-integrity/${conflictId}`,
  );

  const { data: caseRows, error: caseError } = await supabase.rpc(
    "admin_list_delivery_provider_integrity_conflicts",
    { p_state: "all", p_limit: 200 },
  );

  if (caseError) {
    return (
      <section className="mx-auto max-w-5xl px-4 py-12 sm:px-6">
        <AdminStatusMessage type="error" title="Integrity case unavailable">
          The private case record could not be loaded. No evidence or
          resolution history was displayed.
        </AdminStatusMessage>
        <Link href="/admin/provider-integrity" className="mt-6 inline-flex text-sm font-extrabold text-[#8D681D] underline">
          Back to provider integrity
        </Link>
      </section>
    );
  }

  const cases = (caseRows ?? []) as unknown as IntegrityCase[];
  const integrityCase = cases.find(
    (item) => String(item.conflict_id) === conflictId,
  );

  if (!integrityCase) notFound();

  const [evidenceResult, historyResult] = await Promise.all([
    supabase.rpc("admin_list_delivery_provider_integrity_evidence", {
      p_conflict_id: conflictId,
      p_limit: 500,
    }),
    supabase.rpc("admin_list_delivery_provider_integrity_history", {
      p_conflict_id: conflictId,
      p_limit: 500,
    }),
  ]);

  if (evidenceResult.error || historyResult.error) {
    return (
      <section className="mx-auto max-w-5xl px-4 py-12 sm:px-6">
        <AdminStatusMessage type="error" title="Integrity evidence unavailable">
          Evidence and resolution history could not be loaded completely.
          Nothing has been changed. Refresh or ask another database
          administrator to check the authorization and migration state.
        </AdminStatusMessage>
        <Link href="/admin/provider-integrity" className="mt-6 inline-flex text-sm font-extrabold text-[#8D681D] underline">
          Back to provider integrity
        </Link>
      </section>
    );
  }

  const evidence = (evidenceResult.data ?? []) as unknown as IntegrityEvidence[];
  const history = (historyResult.data ?? []) as unknown as IntegrityHistory[];
  const reopened = integrityCase.state === "open" &&
    history.some((item) => item.action === "reopened");

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
      <div className="mb-8 flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">
            Admin · Provider Integrity · Case #{conflictId}
          </p>
          <h1 className="mt-3 break-all font-[var(--font-heading)] text-4xl font-semibold sm:text-5xl">
            {integrityCase.recipient_email}
          </h1>
          <p className="mt-3 text-[#7C715F]">
            {anomalyLabels[integrityCase.anomaly_type] ?? integrityCase.anomaly_type}
          </p>
        </div>
        <Link
          href="/admin/provider-integrity"
          className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-5 py-3 text-sm font-extrabold text-[#26231F]"
        >
          Back to open cases
        </Link>
      </div>

      {notices.updated === "resolved" ? (
        <div className="mb-6">
          <AdminStatusMessage type="success" title="Resolution recorded">
            The administrator note was added to the immutable history. New
            distinct provider evidence will reopen this case automatically.
          </AdminStatusMessage>
        </div>
      ) : null}
      {notices.error === "note_required" ? (
        <div className="mb-6">
          <AdminStatusMessage type="error" title="A resolution note is required">
            Enter a meaningful explanation between 12 and 2,000 characters.
          </AdminStatusMessage>
        </div>
      ) : null}
      {notices.error === "already_resolved" ? (
        <div className="mb-6">
          <AdminStatusMessage type="warning" title="This case is already resolved">
            Refresh the case before taking another action. A new distinct
            provider event will reopen it if another conflict is detected.
          </AdminStatusMessage>
        </div>
      ) : null}
      {notices.error === "failed" ? (
        <div className="mb-6">
          <AdminStatusMessage type="error" title="Resolution was not recorded">
            The database did not confirm this action. The case remains
            unchanged; refresh and inspect its current state before retrying.
          </AdminStatusMessage>
        </div>
      ) : null}

      {reopened ? (
        <div className="mb-6">
          <AdminStatusMessage type="warning" title="Reopened after new provider evidence">
            This case was previously resolved. New distinct conflict evidence
            arrived afterward, so the case is open again. The earlier
            resolution and its audit entry remain preserved below.
          </AdminStatusMessage>
        </div>
      ) : null}

      <section className="deed-card p-6 sm:p-8">
        <div className="flex flex-wrap items-center gap-2">
          <span className={`rounded-full px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] ${integrityCase.state === "open" ? "bg-[#FFF0EC] text-[#8D381D]" : "bg-[#EFF7ED] text-[#3F6E39]"}`}>
            {integrityCase.state === "open" ? "Open · review required" : "Resolved"}
          </span>
          <span className="rounded-full bg-[#FFF8EA] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">
            {evidence.length} evidence record{evidence.length === 1 ? "" : "s"}
          </span>
        </div>
        <div className="mt-5 grid gap-3 sm:grid-cols-2">
          <Field label="First detected" value={formatDate(integrityCase.first_detected_at)} />
          <Field label="Last detected" value={formatDate(integrityCase.last_detected_at)} />
          <Field label="Resolved at" value={formatDate(integrityCase.resolved_at)} />
          <Field label="Current resolution note" value={integrityCase.resolution_note} />
        </div>
      </section>

      {integrityCase.state === "open" ? (
        <section className="mt-6 rounded-[2rem] border border-amber-200 bg-[#FFF8EA] p-6 sm:p-8">
          <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">
            Administrator action
          </p>
          <h2 className="mt-2 font-[var(--font-heading)] text-3xl font-semibold">
            Record a resolution
          </h2>
          <p className="mt-2 max-w-2xl text-sm leading-7 text-[#5F5548]">
            Resolve only after reviewing the preserved provider evidence and
            confirming the operational follow-up. This does not remove the
            evidence, reverse a complaint, or clear a permanent-bounce hold.
          </p>
          <form action={resolveProviderIntegrityConflict} className="mt-5">
            <input type="hidden" name="conflict_id" value={conflictId} />
            <label htmlFor="resolution_note" className="text-sm font-extrabold text-[#26231F]">
              Resolution explanation <span aria-hidden="true">*</span>
              <textarea
                id="resolution_note"
                name="resolution_note"
                required
                minLength={12}
                maxLength={2000}
                rows={5}
                className="mt-2 w-full rounded-2xl border border-amber-200 bg-white p-4 text-sm leading-7 outline-none focus:border-amber-500"
                placeholder="Describe what was reviewed, what was confirmed, and any follow-up taken."
              />
            </label>
            <p className="mt-2 text-xs leading-6 text-[#7C715F]">
              Required · 12–2,000 characters. This note becomes part of the
              append-only administrator history.
            </p>
            <button
              type="submit"
              className="focus-ring mt-5 rounded-full bg-[#D9A441] px-6 py-3 text-sm font-extrabold text-[#26231F]"
            >
              Record resolution
            </button>
          </form>
        </section>
      ) : (
        <div className="mt-6">
          <AdminStatusMessage type="success" title="This case is resolved">
            The resolution note remains in the audit trail. A new distinct
            provider conflict will reopen the case automatically.
          </AdminStatusMessage>
        </div>
      )}

      <section className="mt-8">
        <div className="mb-4">
          <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">
            Immutable provider evidence
          </p>
          <h2 className="mt-2 font-[var(--font-heading)] text-3xl font-semibold">
            Evidence records
          </h2>
          <p className="mt-2 text-sm leading-7 text-[#7C715F]">
            Normalized event fields and fingerprints only. Original webhook
            request bodies and provider diagnostics are not exposed here.
          </p>
        </div>
        {evidence.length ? (
          <div className="grid gap-4">
            {evidence.map((item) => (
              <article key={String(item.evidence_id)} className="deed-card p-5 sm:p-6">
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <p className="font-extrabold text-[#26231F]">
                    {item.event_type} · evidence #{String(item.evidence_id)}
                  </p>
                  <span className="text-xs font-bold text-[#7C715F]">
                    {formatDate(item.observed_at)}
                  </span>
                </div>
                <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                  <Field label="Event ID" value={item.event_id} />
                  <Field label="Related event ID" value={item.related_event_id} />
                  <Field label="Provider email ID" value={item.provider_email_id} />
                  <Field label="Provider suppression ID" value={item.provider_suppression_id} />
                  <Field label="Provider event time" value={formatDate(item.provider_created_at)} />
                  <Field label="Bounce type" value={item.bounce_type} />
                  <Field label="Failure class" value={item.failure_class} />
                  <Field label="Suppression reason" value={item.suppression_reason} />
                  <Field label="Suppression origin" value={item.suppression_origin} />
                  <Field label="Suppression source ID" value={item.suppression_source_id} />
                  <Field label="Suppression event time" value={formatDate(item.suppression_created_at)} />
                  <Field label="Stored event ID" value={item.stored_event_id} />
                  <Field label="Stored recipient" value={item.stored_recipient_email} />
                  <Field label="Evidence source" value={item.evidence_source} />
                  <Field label="Payload fingerprint" value={item.payload_fingerprint} />
                </div>
              </article>
            ))}
          </div>
        ) : (
          <div className="deed-card p-6 text-sm text-[#7C715F]">
            No evidence rows were returned for this case.
          </div>
        )}
      </section>

      <section className="mt-8">
        <div className="mb-4">
          <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">
            Append-only audit
          </p>
          <h2 className="mt-2 font-[var(--font-heading)] text-3xl font-semibold">
            Resolution and reopening history
          </h2>
        </div>
        {history.length ? (
          <ol className="space-y-3">
            {history.map((item) => (
              <li key={String(item.history_id)} className="deed-card p-5">
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <p className="font-extrabold text-[#26231F]">
                    {item.action === "reopened"
                      ? "Reopened after new provider evidence"
                      : "Resolved by an administrator"}
                  </p>
                  <time className="text-xs font-bold text-[#7C715F]">
                    {formatDate(item.created_at)}
                  </time>
                </div>
                <p className="mt-2 whitespace-pre-wrap text-sm leading-7 text-[#5F5548]">
                  {item.note}
                </p>
                {item.evidence_id ? (
                  <p className="mt-2 text-xs font-bold text-[#7C715F]">
                    Evidence #{String(item.evidence_id)}
                  </p>
                ) : null}
              </li>
            ))}
          </ol>
        ) : (
          <div className="deed-card p-6 text-sm text-[#7C715F]">
            No resolution or reopening actions have been recorded.
          </div>
        )}
      </section>
    </section>
  );
}
