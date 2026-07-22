import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { createOffering } from "./actions";

export default async function NewOfferingPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const supabase = await createClient({ allowMissingEnv: true });
  const { data } = supabase ? await supabase.auth.getUser() : { data: { user: null } };
  const params = await searchParams;

  if (supabase && !data.user) redirect("/login?next=/offerings/new");

  return (
    <section className="mx-auto max-w-3xl px-4 py-12 sm:px-6">
      <div className="mb-8">
        <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Share an Offering</p>
        <h1 className="mt-3 font-[var(--font-heading)] text-5xl font-semibold">What kind of light are you sharing?</h1>
        <p className="mt-4 leading-8 text-[#7C715F]">
          Share to inspire, not to show superiority. Protect the dignity of people you helped.
        </p>
      </div>

      {params.error ? <p className="mb-5 rounded-2xl bg-[#FFF4DC] p-4 text-sm font-semibold text-[#8D381D]">{params.error}</p> : null}

      <form action={createOffering} className="deed-card space-y-6 p-6 sm:p-8">
        <div className="rounded-3xl border border-[rgba(217,164,65,0.25)] bg-[#FFF8EA] p-5">
          <p className="font-[var(--font-heading)] text-2xl font-semibold">Before you share</p>
          <p className="mt-2 leading-7 text-[#5F5548]">
            Share to inspire, not to show superiority. Protect the dignity of people you helped. Goodness is most beautiful when it does not humiliate anyone.
          </p>
        </div>

        <label className="block text-sm font-bold text-[#5F5548]">
          Offering type
          <select name="offering_type" className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]" defaultValue="good_deed">
            <option value="good_deed">Good Deed</option>
            <option value="goodness_invitation">Goodness Invitation</option>
            <option value="gratitude">Gratitude</option>
            <option value="beauty_reminder">Beauty Reminder</option>
            <option value="quiet_goodness">Quiet Goodness</option>
            <option value="community_need">Community Need</option>
          </select>
        </label>

        <label className="block text-sm font-bold text-[#5F5548]">
          Title
          <input name="title" className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]" placeholder="A small kindness at the bus stop" required />
        </label>

        <label className="block text-sm font-bold text-[#5F5548]">
          What happened?
          <textarea name="body" className="mt-2 min-h-40 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]" placeholder="Share the story in a way that protects dignity." required />
        </label>

        <label className="block text-sm font-bold text-[#5F5548]">
          What can others take from this?
          <textarea name="takeaway" className="mt-2 min-h-24 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]" placeholder="What small deed could others try?" />
        </label>

        <div className="grid gap-3 sm:grid-cols-2">
          <label className="flex items-center gap-3 rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white/75 p-4 text-sm font-bold text-[#5F5548]">
            <input name="is_anonymous" type="checkbox" />
            Post as Anonymous Light
          </label>
          <label className="flex items-center gap-3 rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white/75 p-4 text-sm font-bold text-[#5F5548]">
            <input name="allow_reflections" type="checkbox" defaultChecked />
            Allow Reflections
          </label>
        </div>

        <button className="focus-ring w-full rounded-full bg-[#D9A441] px-6 py-3 font-extrabold text-[#26231F] shadow-[0_10px_25px_rgba(217,164,65,0.30)]" type="submit">
          Submit Offering for Review
        </button>
      </form>
    </section>
  );
}
