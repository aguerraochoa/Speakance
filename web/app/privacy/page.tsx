import Link from "next/link";

export const metadata = {
  title: "Privacy Policy • Speakance"
};

export default function PrivacyPage() {
  return (
    <main className="docShell">
      <div className="topbar" style={{ marginBottom: 14 }}>
        <div className="brand">
          <span>Speakance</span>
        </div>
        <nav className="nav">
          <Link href="/">Home</Link>
          <Link href="/terms">Terms</Link>
        </nav>
      </div>

      <section className="panel docCard">
        <div className="eyebrow">Privacy Policy</div>
        <h1>Speakance Privacy Policy</h1>
        <p>Last updated: February 24, 2026</p>

        <p>
          This is a starter privacy policy page for Speakance. Replace this content with your final legal
          policy before App Store submission. The text below is a product-oriented summary, not legal advice.
        </p>

        <h2>What Speakance does</h2>
        <p>
          Speakance helps users capture expenses by voice or text, organize them into a ledger, and view
          spending insights. Some processing may use third-party services you configure (for example Supabase
          and AI parsing providers).
        </p>

        <h2>Data you provide</h2>
        <ul>
          <li>Account email and authentication data</li>
          <li>Expense descriptions, amounts, categories, dates, and payment method labels</li>
          <li>Optional voice recordings and transcriptions for expense capture</li>
        </ul>

        <h2>How data is used</h2>
        <ul>
          <li>To create and sync your expense records</li>
          <li>To parse voice/text into structured expenses</li>
          <li>To provide analytics, filters, and reconciliation features</li>
        </ul>

        <h2>Third-party services</h2>
        <p>
          Speakance may rely on backend and AI providers configured by the app operator. You should list all
          providers and link to their policies in your final version.
        </p>

        <h2>Contact</h2>
        <p>
          Add your support email or website contact form here.
        </p>
      </section>
    </main>
  );
}
