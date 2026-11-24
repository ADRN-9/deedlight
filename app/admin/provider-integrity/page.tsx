import Link from "next/link";
import { AdminEmptyState } from "@/components/admin/admin-empty-state";
import { AdminStatusMessage } from "@/components/admin/admin-status-message";
import { requireDatabaseAdmin } from "@/lib/auth/admin";

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

const anomalyLabels: Record<string, string> = {
  duplicate_event_id_conflict: "Conflicting event identifier",
  contradictory_terminal_outcome: "Contradictory delivery outcome",
  suppression_event_timestamp_conflict: "Conflicting suppression timeline",
  provider_email_recipient_conflict: "Provider email recipient mismatch",
  provider_suppression_recipient_conflict: "Provider suppression recipient mismatch",
};

function formatDate(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? "Unknown time"
    : new Intl.DateTimeFormat("en", {
        dateStyle: "medium",
        timeStyle: "short",
        timeZone: "UTC",
      }).format(date) + " UTC";
}

export default async function AdminProviderIntegrityPage() {
  const { supabase } = await requireDatabaseAdmin("/admin/provider-integrity");
  const { data, error } = await supabase.rpc(
    "admin_list_delivery_provider_integrity_conflicts",
    { p_state: "open", p_limit: 200 },
  );

  const cases = (data ?? []) as unknown as IntegrityCase[];

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
      <div className="mb-8 flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">
            Admin · Delivery Integrity
          </p>
          <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">
            Provider integrity review
          </h1>
          <p className="mt-3 max-w-2xl leading-8 text-[#7C715F]">
            Review unresolved provider conflicts without changing the original
            delivery record or its suppression protections.
          </p>
        </div>
        <Link
          href="/admin"
          className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-5 py-3 text-sm font-extrabold text-[#26231F]"
        >
          Back to Admin
        </Link>
      </div>

      <AdminStatusMessage type="info" title="Private administrator workspace">
        Recipient addresses and normalized provider identifiers are visible
        only to database-backed administrators. Raw webhook bodies are never
        displayed or stored in this review.
      </AdminStatusMessage>

      {error ? (
        <div className="mt-7">
          <AdminStatusMessage type="error" title="Integrity cases unavailable">
            The private case list could not be loaded. No provider evidence was
            displayed. Refresh or ask another database administrator to check
            the database authorization and migration state.
          </AdminStatusMessage>
        </div>
      ) : cases.length === 0 ? (
        <div className="mt-7">
          <AdminEmptyState
            title="No unresolved provider conflicts"
            description="There are no open integrity cases in the current review window. New distinct provider evidence will reopen a resolved case automatically."
          />
        </div>
      ) : (
        <div className="mt-7 space-y-4">
          <p className="text-sm font-bold text-[#7C715F]">
            Showing the {cases.length} most recently detected open cases
            (maximum 200).
          </p>
          {cases.map((item) => (
            <article
              key={String(item.conflict_id)}
              className="deed-card p-5 sm:p-6"
            >
              <div className="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="rounded-full bg-[#FFF0EC] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D381D]">
                      Open · needs review
                    </span>
                    <span className="rounded-full bg-[#FFF8EA] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">
                      {anomalyLabels[item.anomaly_type] ?? item.anomaly_type}
                    </span>
                  </div>
                  <h2 className="mt-3 break-all font-[var(--font-heading)] text-2xl font-semibold">
                    {item.recipient_email}
                  </h2>
                  <div className="mt-3 grid gap-2 text-sm text-[#5F5548] sm:grid-cols-2">
                    <p>Case #{String(item.conflict_id)}</p>
                    <p>{item.evidence_count} evidence record{item.evidence_count === 1 ? "" : "s"}</p>
                    <p>First detected: {formatDate(item.first_detected_at)}</p>
                    <p>Last detected: {formatDate(item.last_detected_at)}</p>
                  </div>
                </div>
                <Link
                  href={`/admin/provider-integrity/${item.conflict_id}`}
                  className="focus-ring inline-flex shrink-0 items-center justify-center rounded-full bg-[#D9A441] px-5 py-3 text-sm font-extrabold text-[#26231F]"
                >
                  Inspect evidence
                </Link>
              </div>
            </article>
          ))}
        </div>
      )}
    </section>
  );
}
