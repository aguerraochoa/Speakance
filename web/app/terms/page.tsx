import Link from "next/link";

export const metadata = {
  title: "Terms of Use • Speakance"
};

export default function TermsPage() {
  return (
    <main className="docShell">
      <div className="topbar" style={{ marginBottom: 14 }}>
        <div className="brand">
          <span>Speakance</span>
        </div>
        <nav className="nav">
          <Link href="/">Home</Link>
          <Link href="/privacy">Privacy</Link>
        </nav>
      </div>

      <section className="panel docCard">
        <div className="eyebrow">Terms of Use</div>
        <h1>Speakance Terms of Use</h1>
        <p>Last updated: February 24, 2026</p>

        <p>
          This is a starter Terms page for Speakance. Replace this with your final legal terms before public
          release. The text below is not legal advice.
        </p>

        <h2>Use of the app</h2>
        <p>
          Speakance is provided as a tool for recording and organizing personal expenses. You are responsible
          for reviewing entries and verifying financial records.
        </p>

        <h2>Accounts</h2>
        <p>
          You are responsible for maintaining the confidentiality of your account credentials and for activity
          that occurs under your account.
        </p>

        <h2>Data accuracy</h2>
        <p>
          Parsing and categorization features may be automated and may make mistakes. Users should review and
          correct entries as needed.
        </p>

        <h2>Availability</h2>
        <p>
          The service may change, be interrupted, or be updated over time. Features may vary by version.
        </p>

        <h2>Contact</h2>
        <p>Add your support/legal contact information here.</p>
      </section>
    </main>
  );
}
