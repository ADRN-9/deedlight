"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type OfferingType =
  | "good_deed"
  | "goodness_invitation"
  | "gratitude"
  | "beauty_reminder"
  | "quiet_goodness"
  | "community_need";

type Step = 1 | 2 | 3 | 4;

const OFFERING_TYPES: Array<{ value: OfferingType; title: string; description: string }> = [
  { value: "good_deed", title: "Good Deed", description: "Something good you did." },
  { value: "goodness_invitation", title: "Goodness Invitation", description: "A deed you invite others to try." },
  { value: "gratitude", title: "Gratitude", description: "Goodness you received or witnessed." },
  { value: "beauty_reminder", title: "Beauty Reminder", description: "A moment that restored hope." },
  { value: "quiet_goodness", title: "Quiet Goodness", description: "Share without showing yourself." },
  { value: "community_need", title: "Community Need", description: "A need that should receive extra review." }
];

const TYPE_LABELS: Record<OfferingType, string> = {
  good_deed: "Good Deed",
  goodness_invitation: "Goodness Invitation",
  gratitude: "Gratitude",
  beauty_reminder: "Beauty Reminder",
  quiet_goodness: "Quiet Goodness",
  community_need: "Community Need"
};

function normalizeMediaType(url: string) {
  const clean = url.trim().toLowerCase();
  if (!clean) return null;
  if (/\.(mp4|mov|webm|m4v)(\?.*)?$/.test(clean)) return "video";
  return "image";
}

function validateDraft(input: {
  offeringType: OfferingType;
  title: string;
  body: string;
  takeaway: string;
  mediaUrl: string;
}) {
  const errors: string[] = [];
  const title = input.title.trim();
  const body = input.body.trim();
  const takeaway = input.takeaway.trim();
  const mediaUrl = input.mediaUrl.trim();

  if (!input.offeringType) errors.push("Choose what kind of Offering this is.");
  if (title.length < 8) errors.push("Write a clearer title, at least 8 characters.");
  if (body.length < 40) errors.push("Share the story with a little more detail, at least 40 characters.");
  if (takeaway.length < 15) errors.push("Add a small deed others can try, at least 15 characters.");

  if (mediaUrl && !/^https?:\/\//i.test(mediaUrl)) {
    errors.push("Media URL must start with http:// or https://.");
  }

  return errors;
}

export function CreateOfferingForm({
  defaultAnonymous = false,
}: {
  defaultAnonymous?: boolean;
}) {
  const router = useRouter();
  const [step, setStep] = useState<Step>(1);
  const [offeringType, setOfferingType] = useState<OfferingType>("good_deed");
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [takeaway, setTakeaway] = useState("");
  const [mediaUrl, setMediaUrl] = useState("");
  const [isAnonymous, setIsAnonymous] = useState(defaultAnonymous);
  const [allowReflections, setAllowReflections] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);
  const [success, setSuccess] = useState<string | null>(null);

  const validationErrors = useMemo(
    () => validateDraft({ offeringType, title, body, takeaway, mediaUrl }),
    [offeringType, title, body, takeaway, mediaUrl]
  );

  function nextFromType() {
    setErrors([]);
    setStep(2);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  function goToWriteStep() {
    setErrors([]);
    setStep(3);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  function goToPreview() {
    const nextErrors = validateDraft({ offeringType, title, body, takeaway, mediaUrl });
    setErrors(nextErrors);

    if (nextErrors.length === 0) {
      setStep(4);
      window.scrollTo({ top: 0, behavior: "smooth" });
    }
  }

  async function submitOffering() {
    const nextErrors = validateDraft({ offeringType, title, body, takeaway, mediaUrl });
    if (nextErrors.length > 0) {
      setErrors(nextErrors);
      setStep(3);
      window.scrollTo({ top: 0, behavior: "smooth" });
      return;
    }

    setSubmitting(true);
    setErrors([]);
    setSuccess(null);

    try {
      const supabase = createClient();
      const { data: userData, error: userError } = await supabase.auth.getUser();

      if (userError || !userData.user) {
        setErrors(["Please sign in again before submitting your Offering."]);
        setSubmitting(false);
        return;
      }

      const trimmedMediaUrl = mediaUrl.trim();
      const { error } = await supabase.from("offerings").insert({
        user_id: userData.user.id,
        offering_type: offeringType,
        title: title.trim(),
        body: body.trim(),
        takeaway: takeaway.trim(),
        media_url: trimmedMediaUrl || null,
        media_type: trimmedMediaUrl ? normalizeMediaType(trimmedMediaUrl) : null,
        is_anonymous: isAnonymous,
        allow_reflections: allowReflections,
        status: "pending"
      });

      if (error) {
        setErrors([error.message || "Offering could not be submitted. Please try again."]);
        setSubmitting(false);
        return;
      }

      setSuccess("Thank you. Your Offering is being reviewed so Deedlight remains safe, dignified, and sincere.");
      setSubmitting(false);

      setTimeout(() => {
        router.push("/journey?offering=submitted");
        router.refresh();
      }, 900);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Offering could not be submitted. Please try again.";
      setErrors([message]);
      setSubmitting(false);
    }
  }

  return (
    <section className="mx-auto max-w-4xl rounded-[28px] border border-[#ead7ad] bg-white/90 p-8 shadow-[0_24px_70px_rgba(38,35,31,0.10)]">
      <div className="mb-8">
        <p className="text-xs font-bold uppercase tracking-[0.35em] text-[#9a6a10]">Share an Offering</p>
        <h1 className="mt-3 text-4xl font-bold tracking-tight text-[#26231F]">Prepare a light with care.</h1>
        <p className="mt-3 max-w-2xl text-[#7C715F]">
          Share goodness to inspire, not to impress. Your Offering will be reviewed before it becomes public.
        </p>
      </div>

      {errors.length > 0 && (
        <div className="mb-6 rounded-2xl border border-[#f0c88f] bg-[#fff4dc] p-4 text-sm font-semibold text-[#9a3d1a]">
          <p className="font-bold">Please fix this before submitting:</p>
          <ul className="mt-2 list-disc space-y-1 pl-5">
            {errors.map((error) => (
              <li key={error}>{error}</li>
            ))}
          </ul>
        </div>
      )}

      {success && (
        <div className="mb-6 rounded-2xl border border-[#b7d9ae] bg-[#eff9ec] p-4 text-sm font-semibold text-[#315d2b]">
          {success}
        </div>
      )}

      {step === 1 && (
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.28em] text-[#9a6a10]">Step 1</p>
          <h2 className="mt-2 text-3xl font-bold text-[#26231F]">What kind of light are you sharing?</h2>
          <div className="mt-6 grid gap-4 md:grid-cols-2">
            {OFFERING_TYPES.map((type) => (
              <button
                key={type.value}
                type="button"
                onClick={() => setOfferingType(type.value)}
                className={`rounded-3xl border p-6 text-left transition ${
                  offeringType === type.value
                    ? "border-[#D9A441] bg-[#FFF4DC] shadow-[0_10px_28px_rgba(217,164,65,0.16)]"
                    : "border-[#ead7ad] bg-white hover:bg-[#FFF8EA]"
                }`}
              >
                <h3 className="text-xl font-bold text-[#26231F]">{type.title}</h3>
                <p className="mt-2 text-sm text-[#7C715F]">{type.description}</p>
              </button>
            ))}
          </div>
          <div className="mt-8 flex justify-end">
            <button type="button" onClick={nextFromType} className="rounded-full bg-[#D9A441] px-8 py-3 font-bold text-[#26231F]">
              Continue
            </button>
          </div>
        </div>
      )}

      {step === 2 && (
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.28em] text-[#9a6a10]">Step 2</p>
          <h2 className="mt-2 text-3xl font-bold text-[#26231F]">Before you share</h2>
          <div className="mt-6 rounded-3xl border border-[#ead7ad] bg-[#FFF8EA] p-6">
            <p className="text-lg font-bold text-[#26231F]">Share to inspire, not to show superiority.</p>
            <p className="mt-3 leading-7 text-[#7C715F]">
              Protect the dignity of people you helped. Goodness is most beautiful when it does not humiliate anyone.
            </p>
          </div>
          <div className="mt-8 flex flex-wrap justify-between gap-3">
            <button type="button" onClick={() => setStep(1)} className="rounded-full border border-[#ead7ad] bg-white px-7 py-3 font-bold text-[#26231F]">
              Back
            </button>
            <button type="button" onClick={goToWriteStep} className="rounded-full bg-[#D9A441] px-8 py-3 font-bold text-[#26231F]">
              I understand
            </button>
          </div>
        </div>
      )}

      {step === 3 && (
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.28em] text-[#9a6a10]">Step 3</p>
          <h2 className="mt-2 text-3xl font-bold text-[#26231F]">Write your Offering</h2>
          <div className="mt-6 space-y-5">
            <label className="block">
              <span className="font-bold text-[#4a4033]">Title</span>
              <input
                value={title}
                onChange={(event) => setTitle(event.target.value)}
                className="mt-2 w-full rounded-2xl border border-[#ead7ad] bg-white px-4 py-3 outline-none focus:border-[#D9A441]"
                placeholder="Call someone who feels forgotten"
              />
            </label>
            <label className="block">
              <span className="font-bold text-[#4a4033]">What happened or what are you inviting others to try?</span>
              <textarea
                value={body}
                onChange={(event) => setBody(event.target.value)}
                className="mt-2 min-h-36 w-full rounded-2xl border border-[#ead7ad] bg-white px-4 py-3 outline-none focus:border-[#D9A441]"
                placeholder="Share the story in a way that protects dignity."
              />
            </label>
            <label className="block">
              <span className="font-bold text-[#4a4033]">Small deed others can try</span>
              <textarea
                value={takeaway}
                onChange={(event) => setTakeaway(event.target.value)}
                className="mt-2 min-h-24 w-full rounded-2xl border border-[#ead7ad] bg-white px-4 py-3 outline-none focus:border-[#D9A441]"
                placeholder="One short call can remind someone that they still matter."
              />
            </label>
            <label className="block">
              <span className="font-bold text-[#4a4033]">Optional image/video URL</span>
              <input
                value={mediaUrl}
                onChange={(event) => setMediaUrl(event.target.value)}
                className="mt-2 w-full rounded-2xl border border-[#ead7ad] bg-white px-4 py-3 outline-none focus:border-[#D9A441]"
                placeholder="https://..."
              />
            </label>
            <div className="grid gap-3 md:grid-cols-2">
              <label className="flex items-start gap-3 rounded-2xl border border-[#ead7ad] bg-[#FFF8EA] p-4">
                <input type="checkbox" checked={isAnonymous} onChange={(event) => setIsAnonymous(event.target.checked)} className="mt-1" />
                <span>
                  <span className="block font-bold text-[#26231F]">Post as Anonymous Light</span>
                  <span className="text-sm text-[#7C715F]">Goodness can be shared quietly.</span>
                </span>
              </label>
              <label className="flex items-start gap-3 rounded-2xl border border-[#ead7ad] bg-[#FFF8EA] p-4">
                <input type="checkbox" checked={allowReflections} onChange={(event) => setAllowReflections(event.target.checked)} className="mt-1" />
                <span>
                  <span className="block font-bold text-[#26231F]">Allow Reflections</span>
                  <span className="text-sm text-[#7C715F]">Let others leave kind reflections.</span>
                </span>
              </label>
            </div>
          </div>
          <div className="mt-8 flex flex-wrap justify-between gap-3">
            <button type="button" onClick={() => setStep(2)} className="rounded-full border border-[#ead7ad] bg-white px-7 py-3 font-bold text-[#26231F]">
              Back
            </button>
            <button type="button" onClick={goToPreview} className="rounded-full bg-[#D9A441] px-8 py-3 font-bold text-[#26231F]">
              Preview Offering
            </button>
          </div>
        </div>
      )}

      {step === 4 && (
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.28em] text-[#9a6a10]">Preview</p>
          <h2 className="mt-2 text-3xl font-bold text-[#26231F]">Does this inspire goodness and protect dignity?</h2>
          <article className="mt-6 rounded-3xl border border-[#ead7ad] bg-white p-5">
            <div className="flex h-44 items-center justify-center rounded-3xl bg-[#FFF4DC] text-3xl text-[#9a6a10]">✣</div>
            <div className="mt-5 flex flex-wrap gap-2">
              <span className="rounded-full bg-[#FFF4DC] px-3 py-1 text-xs font-bold uppercase tracking-[0.15em] text-[#9a6a10]">
                {TYPE_LABELS[offeringType]}
              </span>
              {isAnonymous && (
                <span className="rounded-full bg-[#FFF4DC] px-3 py-1 text-xs font-bold uppercase tracking-[0.15em] text-[#9a6a10]">Anonymous Light</span>
              )}
            </div>
            <p className="mt-5 text-sm font-bold text-[#26231F]">{isAnonymous ? "Anonymous Light" : "Your name"}</p>
            <h3 className="mt-3 text-2xl font-bold text-[#26231F]">{title.trim()}</h3>
            <p className="mt-3 leading-7 text-[#5f564b]">{body.trim()}</p>
            <div className="mt-5 rounded-2xl bg-[#FFF8EA] p-4 text-sm font-semibold text-[#4a4033]">
              Small deed others can try: {takeaway.trim()}
            </div>
          </article>
          <div className="mt-8 flex flex-wrap justify-between gap-3">
            <button type="button" onClick={() => setStep(3)} className="rounded-full border border-[#ead7ad] bg-white px-7 py-3 font-bold text-[#26231F]">
              Edit first
            </button>
            <button
              type="button"
              onClick={submitOffering}
              disabled={submitting}
              className="rounded-full bg-[#D9A441] px-8 py-3 font-bold text-[#26231F] disabled:cursor-not-allowed disabled:opacity-60"
            >
              {submitting ? "Submitting..." : "Submit Offering for Review"}
            </button>
          </div>
        </div>
      )}
    </section>
  );
}
