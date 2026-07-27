import type { Metadata, Viewport } from "next";
import { Fraunces, Manrope } from "next/font/google";
import "./globals.css";
import { Footer } from "@/components/layout/footer";
import { MobileNav } from "@/components/layout/mobile-nav";
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

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "https://deedlight.com";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: {
    default: "Deedlight — Where good deeds become light",
    template: "%s | Deedlight"
  },
  description: "A daily social space where good deeds become light — shared, blessed, and carried forward.",
  applicationName: "Deedlight",
  manifest: "/manifest.webmanifest",
  appleWebApp: {
    capable: true,
    title: "Deedlight",
    statusBarStyle: "default"
  },
  icons: {
    icon: [
      { url: "/icons/deedlight-192.png", sizes: "192x192", type: "image/png" },
      { url: "/icons/deedlight-512.png", sizes: "512x512", type: "image/png" }
    ],
    apple: [{ url: "/icons/apple-touch-icon.png", sizes: "180x180", type: "image/png" }]
  },
  openGraph: {
    title: "Deedlight — Where good deeds become light",
    description: "A daily social space for goodness, beauty, and better deeds.",
    url: siteUrl,
    siteName: "Deedlight",
    type: "website",
    images: [
      {
        url: "/og/deedlight-og.png",
        width: 1200,
        height: 630,
        alt: "Deedlight — Where good deeds become light"
      }
    ]
  },
  twitter: {
    card: "summary_large_image",
    title: "Deedlight — Where good deeds become light",
    description: "A daily social space for goodness, beauty, and better deeds.",
    images: ["/og/deedlight-og.png"]
  }
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#D9A441"
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${fraunces.variable} ${manrope.variable}`}>
      <body className="min-h-screen pb-20 font-[var(--font-body)] antialiased md:pb-0">
        <PublicHeader />
        <main>{children}</main>
        <Footer />
        <MobileNav />
      </body>
    </html>
  );
}
