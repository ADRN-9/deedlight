import Link from "next/link";

const mobileItems = [
  { href: "/today", label: "Today", icon: "☀" },
  { href: "/offerings", label: "Offerings", icon: "✦" },
  { href: "/rising", label: "Rising", icon: "↑" },
  { href: "/journey", label: "Journey", icon: "◌" }
];

export function MobileNav() {
  return (
    <nav aria-label="Mobile navigation" className="fixed inset-x-0 bottom-0 z-50 border-t border-[rgba(217,164,65,0.16)] bg-[#FFF8EA]/95 px-3 py-2 shadow-[0_-18px_40px_rgba(38,35,31,0.08)] backdrop-blur-xl md:hidden">
      <div className="mx-auto grid max-w-md grid-cols-4 gap-1">
        {mobileItems.map((item) => (
          <Link key={item.href} href={item.href} className="focus-ring flex min-h-14 flex-col items-center justify-center rounded-2xl px-2 py-2 text-xs font-extrabold text-[#5F5548] transition active:scale-95">
            <span className="text-lg leading-none text-[#8D681D]" aria-hidden="true">{item.icon}</span>
            <span>{item.label}</span>
          </Link>
        ))}
      </div>
    </nav>
  );
}
