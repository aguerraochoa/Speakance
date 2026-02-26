import Link from "next/link";

export const metadata = {
  title: "Support • Speakance"
};

export default function SupportPage() {
  return (
    <main className="docShell">
      <div className="topbar" style={{ marginBottom: 14 }}>
        <div className="brand">
          <span>Speakance</span>
        </div>
        <nav className="nav">
          <Link href="/">Home</Link>
          <Link href="/privacy">Privacy</Link>
          <Link href="/terms">Terms</Link>
        </nav>
      </div>

      <section className="panel docCard">
        <div className="eyebrow">Support</div>
        <h1>Speakance Support</h1>
        <p>Need help with account access, password reset, or expense parsing behavior? Start here.</p>

        <h2>Contact support</h2>
        <p>
          Email: <a href="mailto:support@speakance.app">support@speakance.app</a>
        </p>

        <h2>Common issues</h2>
        <ul>
          <li>If password reset email does not arrive, check spam/junk and confirm the email is typed correctly.</li>
          <li>Voice capture requires microphone access and (optionally) Speech Recognition access on iPhone.</li>
          <li>Some captures may be auto-saved when parsing confidence is high; you can still edit saved expenses in the ledger.</li>
        </ul>

        <h2>Account recovery</h2>
        <p>
          Use the <Link href="/auth/reset">password reset page</Link> if you arrived from a reset email link.
        </p>
      </section>
    </main>
  );
}
