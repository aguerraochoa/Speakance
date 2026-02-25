# Speakance (Project Codename Folder: TalkSpend)

Speakance is an iOS-first, voice-first personal finance app for frictionless expense tracking.

## V1 Focus

- iOS app in SwiftUI
- Voice capture + text fallback
- AI parsing to structured expenses
- Offline capture queue with sync on reconnect
- Supabase backend + Edge Functions

## Repo Structure

- `Sources/` SwiftUI iOS app source
- `Assets.xcassets/` app icons and bundled image assets
- `supabase/` schema migrations + Edge Functions
- `web/` Next.js landing site + policy pages + auth email landing pages
- `docs/` product, architecture, and design source assets

## Start Here

1. Read `/Users/andresguerra/Documents/Non-Work/Apps/TalkSpend/ios/Speakance/docs/v1-spec.md`
2. Read `/Users/andresguerra/Documents/Non-Work/Apps/TalkSpend/ios/Speakance/docs/setup-checklist.md`
3. Generate the iOS project from `/Users/andresguerra/Documents/Non-Work/Apps/TalkSpend/ios/Speakance/project.yml` (with XcodeGen)
4. Create a Supabase project and apply `/Users/andresguerra/Documents/Non-Work/Apps/TalkSpend/ios/Speakance/supabase/migrations/20260222_000001_init.sql`

## Naming

- Public app name: **Speakance**
- Current local folder name: `TalkSpend` (fine as a codename)
