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
        <p>Last updated: February 25, 2026</p>

        <p>
          These Terms of Use govern your use of Speakance, including the iOS app and related web pages.
          By using Speakance, you agree to these terms.
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

        <h2>Acceptable use</h2>
        <p>
          You agree not to use Speakance to violate applicable law, interfere with service operation, attempt
          unauthorized access, or abuse usage limits.
        </p>

        <h2>Availability</h2>
        <p>
          The service may change, be interrupted, or be updated over time. Features may vary by version.
        </p>

        <h2>Termination</h2>
        <p>
          We may suspend or terminate access to the service if required for security, abuse prevention, legal
          compliance, or service maintenance.
        </p>

        <h2>Disclaimer and limitation</h2>
        <p>
          Speakance is provided on an &quot;as is&quot; and &quot;as available&quot; basis. To the maximum extent permitted by law,
          we disclaim warranties and are not liable for indirect, incidental, or consequential damages arising
          from use of the service.
        </p>

        <h2>Contact</h2>
        <p>Questions about these terms: <a href="mailto:support@speakance.app">support@speakance.app</a>.</p>
      </section>
    </main>
  );
}
