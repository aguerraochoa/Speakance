# Speakance V1 (Official Scope)

## Product Definition

Speakance v1 is an iOS-only, voice-first expense tracker focused on fast capture, easy correction, and reliable syncing (including offline capture queueing).

## Core Promise

- Tap record
- Speak an expense
- Confirm/edit quickly
- Save to ledger

## Must-Have Scope

### Platform

- iOS only
- SwiftUI

### Core Capture

- Large voice record button
- Microphone permission flow
- Speech-to-text + AI parsing (server-side)
- Structured extraction: amount, currency, category, date, description/merchant
- Review/edit before save
- Manual text entry fallback (same parser path)

### Offline Mode (Included in V1)

- Multiple captures while offline
- Local queue persistence
- Auto-sync when internet returns
- Retry failed syncs
- Queue status UI: `pending`, `syncing`, `needs_review`, `saved`, `failed`
- Duplicate protection via client-generated IDs

Note: V1 offline mode is offline capture + deferred sync, not offline AI parsing.

### Ledger + Insights

- Recent expense feed
- Monthly total
- Category totals
- Simple trend view

### Categories (Default)

- Food
- Transport
- Entertainment
- Shopping
- Bills
- Other

## Out of Scope (V1)

- Android
- Web app
- Bank sync
- Receipt scanning
- Budget planning/goals
- Apple IAP subscriptions/paywall (V1.1)
- Full offline on-device transcription/parsing

## Usage Guardrails (V1 Defaults)

- Max voice recordings submitted per day (paid): `50`
- Max recording duration: `15s` hard stop
- Suggested UX copy: "One expense per recording"

