import Link from "next/link";

export const metadata = {
  title: "Email Confirmed • Speakance"
};

export default function EmailConfirmedPage() {
  return (
    <main className="docShell">
      <section className="panel docCard" style={{ textAlign: "center" }}>
        <div className="eyebrow" style={{ marginInline: "auto" }}>Email Confirmed</div>
        <h1>Your email is confirmed.</h1>
        <p>
          You can return to the Speakance app and sign in with your email and password.
        </p>

        <div className="ctaRow" style={{ justifyContent: "center" }}>
          <Link className="btn btnPrimary" href="/">
            Back to Speakance site
          </Link>
          <Link className="btn btnGhost" href="/support">Support</Link>
        </div>

        <div className="badgeRow" style={{ justifyContent: "center", marginTop: 18 }}>
          <span className="badge">App confirmation flow</span>
          <span className="badge">Supabase redirect target</span>
        </div>
      </section>
    </main>
  );
}
