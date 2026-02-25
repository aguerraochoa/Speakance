import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Speakance",
  description: "Voice-first expense tracking for fast capture, clean ledgers, and useful insights."
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
