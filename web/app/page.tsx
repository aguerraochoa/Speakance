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
            <div className="snapshotRowTitle">Entertainment · Club table</div>
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
              Capture the expense.
              <br />
              Keep the signal.
            </h1>
            <p>
              Speakance is built for fast capture and clean review. Record one expense at a time, keep a compact
              ledger, and see monthly category trends without the clutter.
            </p>

            <div className="landingActions">
              <a className="landingBtn landingBtnPrimary" href="#" aria-disabled="true">
                App Store • Coming Soon
              </a>
              <Link className="landingBtn landingBtnGhost" href="/support">
                Support
              </Link>
            </div>

            <div className="landingMicroProof">
              <span>Voice + text</span>
              <span>Offline queue</span>
              <span>Trip / Card / Month filters</span>
              <span>Monthly category insights</span>
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
            <div className="bandHeadline">Built around capture first, cleanup second.</div>
            <p>
              The app is optimized for quick input in the moment, then bank-statement style review later with
              compact saved views, card filters, and month slices.
            </p>
          </div>
          <div className="landingBandMetrics">
            <div className="metricCell">
              <div className="metricLabel">Capture modes</div>
              <div className="metricValue">Voice + Text</div>
            </div>
            <div className="metricCell">
              <div className="metricLabel">Queue behavior</div>
              <div className="metricValue">Offline-ready</div>
            </div>
            <div className="metricCell">
              <div className="metricLabel">Review style</div>
              <div className="metricValue">Compact ledger</div>
            </div>
            <div className="metricCell">
              <div className="metricLabel">Insights view</div>
              <div className="metricValue">Month + Year</div>
            </div>
          </div>
        </section>

        <section className="landingGrid">
          <article className="landingPanel">
            <div className="panelEyebrow">Capture</div>
            <h2>Record in the moment</h2>
            <p>
              Tap once, speak one expense, and send. When it is noisy, type it instead. Both routes go through
              the same parsing and review pipeline.
            </p>
          </article>

          <article className="landingPanel">
            <div className="panelEyebrow">Ledger</div>
            <h2>Reconcile with less scrolling</h2>
            <p>
              Saved expenses can be filtered by trip, card, and month. Compact mode is designed so more entries
              fit on screen for statement matching.
            </p>
          </article>

          <article className="landingPanel">
            <div className="panelEyebrow">Insights</div>
            <h2>See totals and category patterns</h2>
            <p>
              Monthly spending mix for current filters plus a year view with stacked category totals by month to
              compare changes over time.
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
