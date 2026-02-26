import Image from "next/image";
import Link from "next/link";
import AmbientParticles from "./components/AmbientParticles";
import AuthRedirectBridge from "./components/AuthRedirectBridge";

function LandingNav() {
  return (
    <header className="landingNav">
      <Link href="/" className="landingBrand" aria-label="Speakance home">
        <Image src="/brand/app-icon.png" alt="" width={34} height={34} />
        <span>Speakance</span>
      </Link>

      <nav className="landingNavLinks" aria-label="Primary">
        <Link href="/support">Support</Link>
        <Link href="/privacy">Privacy</Link>
        <Link href="/terms">Terms</Link>
      </nav>
    </header>
  );
}

function LedgerPreview() {
  return (
    <div className="snapshotShell" aria-label="Speakance ledger preview">
      <div className="snapshotTop">
        <div>
          <div className="snapshotTitle">Ledger • Feb 2026</div>
          <div className="snapshotSub">Saved · Card filter · Compact mode</div>
        </div>
        <div className="snapshotPill">Up to date</div>
      </div>

      <div className="snapshotStats">
        <div className="snapshotStat">
          <div className="snapshotStatLabel">Month</div>
          <div className="snapshotStatValue">US$1,240</div>
        </div>
        <div className="snapshotStat">
          <div className="snapshotStatLabel">Entries</div>
          <div className="snapshotStatValue">34</div>
        </div>
        <div className="snapshotStat">
          <div className="snapshotStatLabel">Queue</div>
          <div className="snapshotStatValue">0</div>
        </div>
      </div>

      <div className="snapshotList">
        <div className="snapshotRow">
          <span className="snapshotDot" style={{ background: "#F97316" }} />
          <div className="snapshotRowBody">
            <div className="snapshotRowTitle">Food · Tacos</div>
            <div className="snapshotRowMeta">Visa · 23 Feb · Text</div>
          </div>
          <div className="snapshotAmount">US$22</div>
        </div>
        <div className="snapshotRow">
          <span className="snapshotDot" style={{ background: "#0EA5E9" }} />
          <div className="snapshotRowBody">
            <div className="snapshotRowTitle">Transport · Uber</div>
            <div className="snapshotRowMeta">Amex · 23 Feb · Voice</div>
          </div>
          <div className="snapshotAmount">US$18</div>
        </div>
        <div className="snapshotRow">
          <span className="snapshotDot" style={{ background: "#6366F1" }} />
          <div className="snapshotRowBody">
            <div className="snapshotRowTitle">Subscriptions · iCloud</div>
            <div className="snapshotRowMeta">Default card · 22 Feb</div>
          </div>
          <div className="snapshotAmount">US$10</div>
        </div>
        <div className="snapshotRow">
          <span className="snapshotDot" style={{ background: "#8B5CF6" }} />
          <div className="snapshotRowBody">
            <div className="snapshotRowTitle">Groceries · Whole Foods</div>
            <div className="snapshotRowMeta">Travel trip · 21 Feb · Voice</div>
          </div>
          <div className="snapshotAmount">US$200</div>
        </div>
      </div>
    </div>
  );
}

export default function HomePage() {
  return (
    <main className="landingRoot">
      <AuthRedirectBridge />
      <div className="landingBackdrop" aria-hidden="true" />
      <AmbientParticles />

      <div className="landingContainer">
        <LandingNav />

        <section className="landingHero">
          <div className="landingHeroCopy">
            <div className="heroSignal">Voice-first expense tracking for iPhone</div>
            <h1>
              Log expenses fast.
              <br />
              Review them clearly.
            </h1>
            <p>
              Speak or type one expense at a time, then review everything in a compact ledger built for quick
              cleanup, filtering, and monthly spending insights.
            </p>

            <div className="landingActions">
              <a
                className="landingBtn landingBtnPrimary"
                href="mailto:support@speakance.app?subject=Speakance%20Beta%20Access"
              >
                Request Beta Access
              </a>
              <Link className="landingBtn landingBtnGhost" href="/support">
                Support
              </Link>
            </div>

            <div className="landingMicroProof">
              <span>Voice + text capture</span>
              <span>Offline queue</span>
              <span>Trip / card / month filters</span>
              <span>Compact ledger review</span>
            </div>
          </div>

          <div className="landingHeroVisual">
            <div className="deviceFrame">
              <div className="deviceGlow" aria-hidden="true" />
              <div className="deviceTop">
                <Image src="/brand/app-icon.png" alt="" width={42} height={42} />
                <div>
                  <div className="deviceBrand">Speakance</div>
                  <div className="deviceMeta">Voice • Ledger • Insights</div>
                </div>
              </div>
              <LedgerPreview />
            </div>
          </div>
        </section>

        <section className="landingBand">
          <div className="landingBandCard">
            <div className="bandKicker">Why it feels fast</div>
            <div className="bandHeadline">Capture first, reconcile later.</div>
            <p>
              Speakance is designed for real-world use: quick capture in the moment, then bank-statement style
              review later with compact views and filters that reduce scrolling.
            </p>
          </div>
          <div className="landingBandMetrics">
            <div className="metricCell">
              <div className="metricLabel">Input</div>
              <div className="metricValue">Voice + Text</div>
            </div>
            <div className="metricCell">
              <div className="metricLabel">Sync behavior</div>
              <div className="metricValue">Offline-ready</div>
            </div>
            <div className="metricCell">
              <div className="metricLabel">Review</div>
              <div className="metricValue">Compact ledger</div>
            </div>
            <div className="metricCell">
              <div className="metricLabel">Insights</div>
              <div className="metricValue">Month + Year</div>
            </div>
          </div>
        </section>

        <section className="landingGrid">
          <article className="landingPanel">
            <div className="panelEyebrow">Capture</div>
            <h2>Record in the moment</h2>
            <p>
              Record one expense at a time by voice or text. Fast capture keeps the habit lightweight, even when
              you are moving.
            </p>
          </article>

          <article className="landingPanel">
            <div className="panelEyebrow">Ledger</div>
            <h2>Reconcile with less scrolling</h2>
            <p>
              Filter saved expenses by trip, card, and month. Compact mode fits more rows on screen for statement
              matching and cleanup.
            </p>
          </article>

          <article className="landingPanel">
            <div className="panelEyebrow">Insights</div>
            <h2>See totals and category patterns</h2>
            <p>
              See category mix for the current month and compare patterns over time with yearly stacked totals by
              month.
            </p>
          </article>
        </section>

        <footer className="landingFooter">
          <div className="landingFooterBrand">
            <Image src="/brand/app-icon.png" alt="" width={20} height={20} />
            <span>Speakance</span>
          </div>
          <div className="landingFooterLinks">
            <Link href="/support">Support</Link>
            <Link href="/privacy">Privacy</Link>
            <Link href="/terms">Terms</Link>
          </div>
        </footer>
      </div>
    </main>
  );
}
