import Link from "next/link";
import type { ComponentProps } from "react";

export function PrimaryLink({ className = "", ...props }: ComponentProps<typeof Link>) {
  return (
    <Link
      {...props}
      className={`focus-ring inline-flex items-center justify-center rounded-full bg-[#D9A441] px-6 py-3 text-sm font-extrabold text-[#26231F] shadow-[0_10px_25px_rgba(217,164,65,0.30)] transition hover:-translate-y-0.5 ${className}`}
    />
  );
}

export function SecondaryLink({ className = "", ...props }: ComponentProps<typeof Link>) {
  return (
    <Link
      {...props}
      className={`focus-ring inline-flex items-center justify-center rounded-full border border-[rgba(217,164,65,0.35)] bg-white/75 px-6 py-3 text-sm font-extrabold text-[#26231F] transition hover:-translate-y-0.5 ${className}`}
    />
  );
}
