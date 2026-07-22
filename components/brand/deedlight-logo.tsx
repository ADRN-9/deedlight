import { Flame } from "lucide-react";

export function DeedlightSymbol() {
  return (
    <span className="inline-flex h-10 w-10 items-center justify-center rounded-2xl bg-[#FFF4DC] text-[#D9A441] shadow-[0_0_24px_rgba(217,164,65,0.20)]">
      <Flame className="h-5 w-5" fill="currentColor" strokeWidth={1.8} aria-hidden="true" />
    </span>
  );
}

export function DeedlightLogo() {
  return (
    <span className="flex items-center gap-3">
      <DeedlightSymbol />
      <span className="font-[var(--font-heading)] text-2xl font-semibold tracking-tight text-[#26231F]">
        Deedlight
      </span>
    </span>
  );
}
