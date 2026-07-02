import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Polder",
  description: "Digitale administratie voor zakelijke restaurantrekeningen — Café Restaurant Polder",
  manifest: "/manifest.json",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover", // vereist voor safe-area op iPhone (sectie 13)
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="nl">
      <body className="min-h-screen bg-neutral-50 text-neutral-900 pt-safe-top pb-safe-bottom pl-safe-left pr-safe-right">
        {children}
      </body>
    </html>
  );
}
