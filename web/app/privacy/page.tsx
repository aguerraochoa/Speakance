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
        <p>Last updated: February 25, 2026</p>

        <p>
          Speakance helps you capture expenses by voice or text, organize them into a ledger, and view spending
          insights. This page explains what information is processed when you use Speakance.
        </p>

        <h2>Information we collect</h2>
        <p>
          We process information you provide directly in the app, including account email, expense details
          (amounts, categories, descriptions, dates, trip labels, and payment method labels), and optional voice
          recordings or transcripts used for voice capture.
        </p>

        <h2>How we use information</h2>
        <ul>
          <li>To authenticate your account and keep your data tied to your profile</li>
          <li>To parse voice or text captures into structured expense records</li>
          <li>To sync your expenses, categories, trips, and payment methods across devices</li>
          <li>To provide ledger views, filters, and insights features</li>
          <li>To measure service usage limits (for example, voice parsing usage)</li>
        </ul>

        <h2>Voice capture and transcription</h2>
        <p>
          If you use voice capture, Speakance records audio on your device and may upload audio temporarily for
          transcription and parsing. Transcribed text is used to create or suggest an expense entry. Parsed
          results should be reviewed by you for accuracy.
        </p>

        <h2>Service providers</h2>
        <p>
          Speakance uses third-party infrastructure providers to operate the service, including Supabase (for
          authentication, database, and storage) and OpenAI APIs (for transcription and/or parsing when enabled).
          These providers process data only to provide the requested functionality.
        </p>

        <h2>Data retention</h2>
        <p>
          Expense records and related metadata remain in your account until you delete them. Temporary uploaded
          voice files are intended to be deleted after processing, but transient failures may delay deletion.
        </p>

        <h2>Security</h2>
        <p>
          We use reasonable technical measures to protect your data in transit and at rest. No method of storage
          or transmission is completely secure, and we cannot guarantee absolute security.
        </p>

        <h2>Your choices</h2>
        <ul>
          <li>You can use text capture instead of voice capture</li>
          <li>You can edit or delete expenses inside the app</li>
          <li>You can remove your account data by contacting support</li>
        </ul>

        <h2>Contact</h2>
        <p>
          For privacy questions or requests, contact <a href="mailto:support@speakance.app">support@speakance.app</a>.
        </p>
      </section>
    </main>
  );
}
