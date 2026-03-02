# Setup Checklist (Starting From Zero)

## Apple / iOS

- Apple ID
- Mac with latest Xcode installed
- Apple Developer Program enrollment (for TestFlight/App Store)
- App Store Connect setup
- Banking/tax forms (before subscriptions)
- Bundle ID reserved (example: `com.yourname.speakance`)

## Backend / AI

- Supabase account + project
- OpenAI account + billing
- Environment variables configured in Supabase Edge Functions
- Supabase Storage bucket `voice-captures` with RLS policies applied (via migrations)
- Supabase Edge Functions deployed (`parse-expense`, `delete-account`)
- Follow deployment runbook: `docs/edge-functions-runbook.md` (includes required `--no-verify-jwt` for `parse-expense` and `delete-account`)
- Separate `dev` and `prod` projects (recommended)

## App Compliance

- Privacy policy URL
- Support email
- Terms of service (recommended)
- App Privacy disclosure entries (App Store Connect)
- Microphone permission copy
- Speech recognition permission copy (if using Apple Speech APIs)
