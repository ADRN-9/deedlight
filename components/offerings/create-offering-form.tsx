"use client";

import { useMemo, useState } from "react";
import { CheckCircle2, Eye, ImageIcon, ShieldCheck, Sparkles } from "lucide-react";
import { createOffering } from "@/app/offerings/new/actions";

const offeringTypes = [
  ["good_deed", "Good Deed", "Something good you did."],
  ["goodness_invitation", "Goodness Invitation", "A deed you invite others to try."],
  ["gratitude", "Gratitude", "Goodness you received or witnessed."],
  ["beauty_reminder", "Beauty Reminder", "A moment that restored hope."],
  ["quiet_goodness", "Quiet Goodness", "Share without showing yourself."],
  ["community_need", "Community Need", "A need that should receive extra review."]
] as const;

const themes = [
  ["kindness", "Kindness"],
  ["courage", "Courage"],
  ["mercy", "Mercy"],
  ["honesty", "Honesty"],
  ["patience", "Patience"],
  ["gratitude", "Gratitude"],
  ["beauty", "Beauty"],
  ["community", "Community"]
] as const;

type Props = {
  error?: string;
};

export function CreateOfferingForm({ error }: Props) {
  const [step, setStep] = useState(1);
  const [offeringType, setOfferingType] = useState("good_deed");
  const [themeSlug, setThemeSlug] = useState("kindness");
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [takeaway, setTakeaway] = useState("");
  const [mediaUrl, setMediaUrl] = useState("");
  const [isAnonymous, setIsAnonymous] = useState(false);
  const [allowReflections, setAllowReflections] = useState(true);

  const selectedType = useMemo(
    () => offeringTypes.find(([value]) => value === offeringType) || offeringTypes[0],
    [offeringType]
  );

  return (
    <form action={createOffering} className="deed-card overflow-hidden">
      <input type="hidden" name="offering_type" value={offeringType} />
      <input type="hidden" name="theme_slug" value={themeSlug} />
      <input type="hidden" name="is_anonymous" value={isAnonymous ? "on" : ""} />
      <input type="hidden" name="allow_reflections" value={allowReflections ? "on" : ""} />

      <div className="border-b border-[rgba(217,164,65,0.16)] bg-white/60 px-6 py-4 sm:px-8">
        <div className="flex flex-wrap gap-2 text-xs font-extrabold uppercase tracking-[0.16em] text-[#8D681D]">
          {["Type", "Dignity", "Write", "Preview"].map((label, index) => {
            const active = step === index + 1;
            const done = step > index + 1;
            return (
              <span key={label} className={`rounded-full px-3 py-1 ${active || done ? "bg-[#FFF4DC] text-[#8D681D]" : "bg-white text-[#9A8D7D]"}`}>
                {done ? "✓ " : ""}{index + 1}. {label}
              </span>
            );
          })}
        </div>
      </div>

      {error ? <div className="mx-6 mt-6 rounded-2xl bg-[#FFF4DC] p-4 text-sm font-semibold text-[#8D381D] sm:mx-8">{error}</div> : null}

      <div className="p-6 sm:p-8">
        {step === 1 ? (
          <section>
            <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Step 1</p>
            <h2 className="mt-2 font-[var(--font-heading)] text-3xl font-semibold">What kind of light are you sharing?</h2>
            <div className="mt-6 grid gap-3 sm:grid-cols-2">
              {offeringTypes.map(([value, label, description]) => {
                const active = offeringType === value;
                return (
                  <button
                    key={value}
                    type="button"
                    onClick={() => setOfferingType(value)}
                    className={`focus-ring rounded-3xl border p-5 text-left transition ${active ? "border-[#D9A441] bg-[#FFF4DC] shadow-[0_0_24px_rgba(217,164,65,0.20)]" : "border-[rgba(217,164,65,0.20)] bg-white/70 hover:bg-white"}`}
                  >
                    <p className="font-[var(--font-heading)] text-xl font-semibold">{label}</p>
                    <p className="mt-2 text-sm leading-6 text-[#7C715F]">{description}</p>
                  </button>
                );
              })}
            </div>
            <div className="mt-7 flex justify-end">
              <button type="button" onClick={() => setStep(2)} className="focus-ring rounded-full bg-[#D9A441] px-6 py-3 font-extrabold text-[#26231F]">
                Continue
              </button>
            </div>
          </section>
        ) : null}

        {step === 2 ? (
          <section>
            <div className="rounded-3xl border border-[rgba(217,164,65,0.25)] bg-[#FFF8EA] p-6">
              <div className="flex items-start gap-4">
                <div className="rounded-full bg-[#FFF4DC] p-3 text-[#8D681D]"><ShieldCheck className="h-6 w-6" /></div>
                <div>
                  <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Before you share</p>
                  <h2 className="mt-2 font-[var(--font-heading)] text-3xl font-semibold">Share with dignity.</h2>
                  <p className="mt-3 leading-8 text-[#5F5548]">
                    Share to inspire, not to show superiority. Protect the dignity of people you helped. Goodness is most beautiful when it does not humiliate anyone.
                  </p>
                  <ul className="mt-5 space-y-2 text-sm font-semibold text-[#5F5548]">
                    <li className="flex gap-2"><CheckCircle2 className="mt-0.5 h-4 w-4 text-[#6F816A]" /> Avoid showing vulnerable people without permission.</li>
                    <li className="flex gap-2"><CheckCircle2 className="mt-0.5 h-4 w-4 text-[#6F816A]" /> Share the lesson, not someone else’s private pain.</li>
                    <li className="flex gap-2"><CheckCircle2 className="mt-0.5 h-4 w-4 text-[#6F816A]" /> Anonymous goodness is welcome.</li>
                  </ul>
                </div>
              </div>
            </div>
            <div className="mt-7 flex justify-between gap-3">
              <button type="button" onClick={() => setStep(1)} className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-6 py-3 font-extrabold text-[#26231F]">
                Back
              </button>
              <button type="button" onClick={() => setStep(3)} className="focus-ring rounded-full bg-[#D9A441] px-6 py-3 font-extrabold text-[#26231F]">
                I understand
              </button>
            </div>
          </section>
        ) : null}

        {step === 3 ? (
          <section className="space-y-5">
            <div>
              <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Step 3</p>
              <h2 className="mt-2 font-[var(--font-heading)] text-3xl font-semibold">Write your Offering.</h2>
              <p className="mt-2 text-sm leading-6 text-[#7C715F]">Selected: <strong>{selectedType[1]}</strong></p>
            </div>

            <label className="block text-sm font-bold text-[#5F5548]">
              Theme
              <select value={themeSlug} onChange={(event) => setThemeSlug(event.target.value)} className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]">
                {themes.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
              </select>
            </label>

            <label className="block text-sm font-bold text-[#5F5548]">
              Title
              <input name="title" value={title} onChange={(event) => setTitle(event.target.value)} className="mt-2 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]" placeholder="A small kindness at the bus stop" required />
            </label>

            <label className="block text-sm font-bold text-[#5F5548]">
              What happened?
              <textarea name="body" value={body} onChange={(event) => setBody(event.target.value)} className="mt-2 min-h-40 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]" placeholder="Share the story in a way that protects dignity." required />
            </label>

            <label className="block text-sm font-bold text-[#5F5548]">
              What can others take from this?
              <textarea name="takeaway" value={takeaway} onChange={(event) => setTakeaway(event.target.value)} className="mt-2 min-h-24 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]" placeholder="What small deed could others try?" />
            </label>

            <label className="block text-sm font-bold text-[#5F5548]">
              Optional image/video URL
              <div className="mt-2 flex items-center gap-3 rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3">
                <ImageIcon className="h-5 w-5 text-[#8D681D]" />
                <input name="media_url" value={mediaUrl} onChange={(event) => setMediaUrl(event.target.value)} className="w-full bg-transparent outline-none" placeholder="https://example.com/image.jpg" />
              </div>
            </label>

            <div className="grid gap-3 sm:grid-cols-2">
              <label className="flex items-center gap-3 rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white/75 p-4 text-sm font-bold text-[#5F5548]">
                <input checked={isAnonymous} onChange={(event) => setIsAnonymous(event.target.checked)} type="checkbox" />
                Post as Anonymous Light
              </label>
              <label className="flex items-center gap-3 rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white/75 p-4 text-sm font-bold text-[#5F5548]">
                <input checked={allowReflections} onChange={(event) => setAllowReflections(event.target.checked)} type="checkbox" />
                Allow Reflections
              </label>
            </div>

            <div className="flex justify-between gap-3 pt-2">
              <button type="button" onClick={() => setStep(2)} className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-6 py-3 font-extrabold text-[#26231F]">
                Back
              </button>
              <button type="button" onClick={() => setStep(4)} className="focus-ring rounded-full bg-[#D9A441] px-6 py-3 font-extrabold text-[#26231F]">
                Preview Offering
              </button>
            </div>
          </section>
        ) : null}

        {step === 4 ? (
          <section>
            <div className="mb-5 flex items-center gap-3">
              <Eye className="h-5 w-5 text-[#8D681D]" />
              <div>
                <p className="text-xs font-extrabold uppercase tracking-[0.2em] text-[#8D681D]">Preview</p>
                <h2 className="font-[var(--font-heading)] text-3xl font-semibold">Does this inspire goodness and protect dignity?</h2>
              </div>
            </div>

            <article className="rounded-3xl border border-[rgba(217,164,65,0.18)] bg-white p-5">
              {mediaUrl ? (
                <div className="mb-4 h-52 rounded-3xl bg-cover bg-center" style={{ backgroundImage: `url(${mediaUrl})` }} />
              ) : (
                <div className="mb-4 flex h-40 items-center justify-center rounded-3xl bg-[radial-gradient(circle_at_30%_15%,rgba(244,199,107,0.55),transparent_34%),linear-gradient(135deg,#FFF4DC,#F8EFE0)] text-[#8D681D]">
                  <Sparkles className="h-8 w-8" />
                </div>
              )}
              <div className="mb-4 flex flex-wrap gap-2">
                <span className="rounded-full bg-[#FFF4DC] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">{selectedType[1]}</span>
                <span className="rounded-full bg-[#FFF8EA] px-3 py-1 text-xs font-extrabold uppercase tracking-[0.14em] text-[#8D681D]">{themes.find(([value]) => value === themeSlug)?.[1]}</span>
              </div>
              <p className="text-sm font-extrabold text-[#26231F]">{isAnonymous ? "Anonymous Light" : "Your name"}</p>
              <h3 className="mt-3 font-[var(--font-heading)] text-3xl font-semibold">{title || "Your Offering title"}</h3>
              <p className="mt-3 whitespace-pre-line leading-8 text-[#5F5548]">{body || "Your story will appear here."}</p>
              {takeaway ? <p className="mt-5 rounded-2xl bg-[#FFF8EA] p-4 text-sm font-bold text-[#5F5548]">Small deed others can try: {takeaway}</p> : null}
            </article>

            <div className="mt-7 flex flex-col-reverse gap-3 sm:flex-row sm:justify-between">
              <button type="button" onClick={() => setStep(3)} className="focus-ring rounded-full border border-[rgba(217,164,65,0.30)] bg-white px-6 py-3 font-extrabold text-[#26231F]">
                Edit first
              </button>
              <button type="submit" className="focus-ring rounded-full bg-[#D9A441] px-6 py-3 font-extrabold text-[#26231F] shadow-[0_10px_25px_rgba(217,164,65,0.30)]">
                Submit Offering for Review
              </button>
            </div>
          </section>
        ) : null}
      </div>
    </form>
  );
}
