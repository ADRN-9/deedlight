import Link from "next/link";
import { DeedlightSymbol } from "@/components/brand/deedlight-logo";

export function Footer() {
  return (
    <footer className="border-t border-[rgba(217,164,65,0.16)] bg-white/50">
      <div className="mx-auto grid max-w-6xl gap-8 px-4 py-10 sm:px-6 md:grid-cols-[1.2fr_1fr]">
        <div>
          <div className="mb-3 flex items-center gap-3">
            <DeedlightSymbol />
            <span className="font-[var(--font-heading)] text-xl font-semibold">Deedlight</span>
          </div>
          <p className="max-w-xl text-sm leading-6 text-[#7C715F]">
            Where good deeds become light. A daily space for goodness, beauty, and better deeds.
          </p>
        </div>
        <div className="grid grid-cols-2 gap-3 text-sm font-semibold text-[#5F5548] sm:grid-cols-4">
          <Link href="/today">Today</Link>
          <Link href="/offerings">Offerings</Link>
          <Link href="/guidelines">Guidelines</Link>
          <Link href="/privacy">Privacy</Link>
        </div>
      </div>
    </footer>
  );
}
