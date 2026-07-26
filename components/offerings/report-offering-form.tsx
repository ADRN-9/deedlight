"use client";

import { useState } from "react";
import { AlertTriangle, Flag } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import type { ReportReason } from "@/lib/types";

const reasons: Array<{ value: ReportReason; label: string; help: string }> = [
  { value: "exposes_vulnerable_person", label: "Exposes a vulnerable person", help: "The post may reveal someone who should be protected." },
  { value: "hate_or_prejudice", label: "Hate or prejudice", help: "The post targets a person or group unfairly." },
  { value: "fake_charity_or_fraud", label: "Fake charity or fraud risk", help: "The post may mislead people or ask for unsafe help." },
  { value: "harassment", label: "Harassment or humiliation", help: "The post shames, pressures, or humiliates someone." },
  { value: "graphic_or_disturbing", label: "Graphic or disturbing", help: "The post may be unsafe or distressing to view." },
  { value: "self_promotion", label: "Mostly self-promotion", help: "The post does not feel like a sincere Offering." },
  { value: "privacy_concern", label: "Privacy concern", help: "The post shares names, locations, or details too openly." },
  { value: "other", label: "Other", help: "Something else needs admin attention." }
];

export function ReportOfferingForm({ offeringId }: { offeringId: string }) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState<ReportReason>("privacy_concern");
  const [details, setDetails] = useState("");
  const [message, setMessage] = useState<string | null>(null);
  const [status, setStatus] = useState<"idle" | "saving" | "success" | "error">("idle");

  async function submitReport() {
    setStatus("saving");
    setMessage(null);

    try {
      const supabase = createClient();
      const {
        data: { user }
      } = await supabase.auth.getUser();

      if (!user) {
        setStatus("error");
        setMessage("Please sign in to report an Offering. Reports help keep Deedlight safe and dignified.");
        return;
      }

      const existing = await supabase
        .from("reports")
        .select("id, status")
        .eq("offering_id", offeringId)
        .eq("reported_by", user.id)
        .in("status", ["open", "reviewing"])
        .limit(1)
        .maybeSingle();

      if (existing.data) {
        setStatus("success");
        setMessage("Thank you. You already have an open report for this Offering, and it is in the admin queue.");
        return;
      }

      const { error } = await supabase.from("reports").insert({
        offering_id: offeringId,
        reported_by: user.id,
        reason,
        details: details.trim() || null,
        status: "open"
      });

      if (error) {
        setStatus("error");
        setMessage(error.message);
        return;
      }

      setStatus("success");
      setDetails("");
      setMessage("Thank you. An admin will review this Offering with care.");
    } catch (error) {
      setStatus("error");
      setMessage(error instanceof Error ? error.message : "The report could not be submitted. Please try again.");
    }
  }

  return (
    <div className="mt-8 rounded-3xl border border-[rgba(217,164,65,0.20)] bg-white p-5">
      <button
        type="button"
        onClick={() => setOpen((value) => !value)}
        className="focus-ring inline-flex items-center gap-2 rounded-full border border-[rgba(38,35,31,0.14)] bg-white px-4 py-2 text-sm font-extrabold text-[#5F5548]"
      >
        <Flag className="h-4 w-4" /> Report dignity concern
      </button>

      {open ? (
        <div className="mt-5 space-y-4">
          <div className="rounded-3xl bg-[#FFF8EA] p-4 text-sm font-semibold leading-7 text-[#5F5548]">
            <div className="mb-2 flex items-center gap-2 font-extrabold text-[#8D681D]"><AlertTriangle className="h-4 w-4" /> Report only real concerns</div>
            Use this if the Offering may harm someone’s dignity, privacy, safety, or trust. Reports are private to admins.
          </div>

          <label className="block text-sm font-extrabold text-[#26231F]" htmlFor="report-reason">Reason</label>
          <select
            id="report-reason"
            value={reason}
            onChange={(event) => setReason(event.target.value as ReportReason)}
            className="w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 font-semibold outline-none focus:border-[#D9A441]"
          >
            {reasons.map((item) => (
              <option key={item.value} value={item.value}>{item.label}</option>
            ))}
          </select>
          <p className="text-xs font-semibold leading-5 text-[#7C715F]">{reasons.find((item) => item.value === reason)?.help}</p>

          <label className="block text-sm font-extrabold text-[#26231F]" htmlFor="report-details">Details for admin, optional</label>
          <textarea
            id="report-details"
            value={details}
            onChange={(event) => setDetails(event.target.value)}
            maxLength={1000}
            className="min-h-28 w-full rounded-2xl border border-[rgba(217,164,65,0.25)] bg-white px-4 py-3 outline-none focus:border-[#D9A441]"
            placeholder="Briefly explain what should be reviewed…"
          />

          {message ? (
            <p className={`rounded-2xl p-3 text-sm font-bold ${status === "success" ? "bg-[#EFF7ED] text-[#3F6E39]" : "bg-[#FFF0EC] text-[#8D381D]"}`}>
              {message}
            </p>
          ) : null}

          <button
            type="button"
            onClick={submitReport}
            disabled={status === "saving"}
            className="focus-ring rounded-full bg-[#D9A441] px-5 py-3 text-sm font-extrabold text-[#26231F] disabled:opacity-60"
          >
            {status === "saving" ? "Sending report…" : "Submit private report"}
          </button>
        </div>
      ) : null}
    </div>
  );
}
