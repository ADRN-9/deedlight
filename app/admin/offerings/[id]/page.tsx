import Link from "next/link";
import { notFound } from "next/navigation";
import { CheckCircle2, EyeOff, PencilLine, ShieldCheck, XCircle } from "lucide-react";
import { requireAdmin } from "@/lib/auth/admin";
import { getAdminOffering } from "@/lib/data/offerings";
import { approveOffering, hideOffering, rejectOffering, requestOfferingEdit } from "./actions";

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

  const author = offering.is_anonymous ? "Anonymous Light" : offering.author_name || "Deedlight member";

  return (
    <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
      <div className="mb-8 flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Admin · Review Offering</p>
          <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">Review with dignity.</h1>
          <p className="mt-3 max-w-2xl leading-8 text-[#7C715F]">Approve only what inspires goodness and protects people’s dignity.</p>
        </div>
        <Link href="/admin/offerings" className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-5 py-3 text-sm font-extrabold text-[#26231F]">
          Back to queue
        </Link>
      </div>

      {notices.updated ? (
        <div className="mb-6 rounded-3xl border border-[rgba(217,164,65,0.25)] bg-[#FFF4DC] p-5 font-bold text-[#5F5548]">
          Offering status updated to <span className="capitalize">{notices.updated.replace("_", " ")}</span>.
        </div>
      ) : null}

      {notices.error ? (
        <div className="mb-6 rounded-3xl bg-[#FFF0EC] p-5 font-bold text-[#8D381D]">{notices.error}</div>
      ) : null}

      <div className="grid gap-6 lg:grid-cols-[1.25fr_0.75fr]">
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
              {offering.is_anonymous ? <span className="rounded-full bg-[#F0EEE8] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#5F5548]">Anonymous</span> : null}
            </div>
            <p className="text-sm font-extrabold text-[#26231F]">{author}</p>
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
            <p className="mt-2 text-sm leading-6 text-[#7C715F]">Add a note when rejecting, requesting edits, or hiding a post.</p>

            <textarea
              name="moderation_note"
              form="reject-form"
              className="mt-5 min-h-28 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]"
              placeholder="Moderation note, if needed…"
            />

            <div className="mt-5 grid gap-3">
              <form action={approveOffering}>
                <input type="hidden" name="id" value={offering.id} />
                <button className="focus-ring flex w-full items-center justify-center gap-2 rounded-full bg-[#D9A441] px-5 py-3 font-extrabold text-[#26231F]" type="submit">
                  <CheckCircle2 className="h-4 w-4" /> Approve and publish
                </button>
              </form>

              <form id="edit-form" action={requestOfferingEdit}>
                <input type="hidden" name="id" value={offering.id} />
                <input type="hidden" name="moderation_note" value="Please revise this Offering so it better protects dignity and inspires goodness." />
                <button className="focus-ring flex w-full items-center justify-center gap-2 rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-5 py-3 font-extrabold text-[#26231F]" type="submit">
                  <PencilLine className="h-4 w-4" /> Request edit
                </button>
              </form>

              <form id="reject-form" action={rejectOffering}>
                <input type="hidden" name="id" value={offering.id} />
                <button className="focus-ring flex w-full items-center justify-center gap-2 rounded-full border border-[#E7B7A5] bg-[#FFF0EC] px-5 py-3 font-extrabold text-[#8D381D]" type="submit">
                  <XCircle className="h-4 w-4" /> Reject
                </button>
              </form>

              <form action={hideOffering}>
                <input type="hidden" name="id" value={offering.id} />
                <input type="hidden" name="moderation_note" value="Hidden by admin review." />
                <button className="focus-ring flex w-full items-center justify-center gap-2 rounded-full border border-[rgba(38,35,31,0.16)] bg-white px-5 py-3 font-extrabold text-[#5F5548]" type="submit">
                  <EyeOff className="h-4 w-4" /> Hide
                </button>
              </form>
            </div>
          </div>
        </aside>
      </div>
    </section>
  );
}

function formatOfferingType(value: string) {
  return value
    .split("_")
    .map((word) => word[0]?.toUpperCase() + word.slice(1))
    .join(" ");
}
