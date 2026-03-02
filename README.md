# Speakance

Speakance is an iOS-first expense tracker focused on low-friction capture and clean visual review.

## What The App Currently Does

- Fast expense capture:
  - Voice recording flow
  - Text fallback input
- AI parsing into structured expenses
- Offline queue with retry/sync when connectivity returns
- Full expense review/edit flow
- Four main tabs:
  - `Capture`
  - `Ledger`
  - `Insights`
  - `Settings`
- Insights:
  - Trip/card/month/currency filters
  - KPI summary cards
  - Spending mix donut + legend
  - Monthly category trend chart
- Settings:
  - Default currency
  - Voice/parser language
  - Categories/trips/payment methods management
  - CSV export
  - JSON backup export/import
  - Tutorial replay

## Product Scope Notes

- Budget/limit tracking is intentionally removed.
- The app is positioned for simple, fast expense logging rather than full budgeting workflows.

## Repo Structure

- `Sources/`: SwiftUI iOS app source
- `Assets.xcassets/`: app icons and bundled image assets
- `supabase/`: schema migrations + Edge Functions
- `web/`: Next.js landing site + policy pages + auth email landing pages
- `docs/`: product, architecture, and design source assets

## Local Setup

1. Read `docs/setup-checklist.md`.
2. Generate the Xcode project from `project.yml` (XcodeGen).
3. Open `Speakance.xcodeproj` in Xcode.
4. Build/run the `Speakance` scheme on iOS Simulator (or device).

## Backend Setup (Optional For Cloud Sync)

1. Create a Supabase project.
2. Apply migrations in `supabase/migrations/`.
3. Configure app environment/auth settings as documented in `docs/`.

## Naming

- Public app name: **Speakance**
