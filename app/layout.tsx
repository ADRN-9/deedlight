import type { Metadata } from "next";
import { Fraunces, Manrope } from "next/font/google";
import "./globals.css";
import { Footer } from "@/components/layout/footer";
import { PublicHeader } from "@/components/layout/public-header";

const fraunces = Fraunces({
  subsets: ["latin"],
  variable: "--font-heading",
  display: "swap"
});

const manrope = Manrope({
  subsets: ["latin"],
  variable: "--font-body",
  display: "swap"
});

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL || "https://deedlight.com"),
  title: {
    default: "Deedlight — Where good deeds become light",
    template: "%s | Deedlight"
  },
  description:
    "A daily social space where good deeds become light — shared, blessed, and carried forward.",
  manifest: "/manifest.webmanifest",
  openGraph: {
    title: "Deedlight",
    description: "Where good deeds become light.",
    url: "https://deedlight.com",
    siteName: "Deedlight",
    type: "website"
  }
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${fraunces.variable} ${manrope.variable}`}>
      <body className="min-h-screen font-[var(--font-body)] antialiased">
        <PublicHeader />
        <main>{children}</main>
        <Footer />
      </body>
    </html>
  );
}
