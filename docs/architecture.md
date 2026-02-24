# Speakance V1 Architecture

## High-Level

- **Client (iOS / SwiftUI)**: voice capture UI, offline queue, review/edit UX, local persistence
- **Supabase**: Auth, Postgres, RLS, Edge Functions
- **OpenAI**: speech-to-text + structured parsing

## Core Flow (Online)

1. User records voice or types text
2. App creates `client_expense_id` (UUID)
3. App sends payload to Edge Function
4. Edge Function enforces limits and validates request
5. Edge Function runs STT (if audio) and parsing
6. Edge Function validates parsed output
7. Expense stored in Supabase (`upsert` by `user_id + client_expense_id`)
8. Structured response returned to app
9. App presents review or success state

## Core Flow (Offline)

1. User records voice (or types text) with no internet
2. App stores queued item locally (app-private storage + local DB)
3. Item appears in feed with queue status
4. On reconnect, sync engine uploads queued items in order
5. Backend processes each item idempotently
6. App updates queue item status and merges saved expense into ledger

## Reliability Rules

- Client-generated `client_expense_id` for idempotency
- Store `captured_at_device` and preserve during sync
- Retries should not double count or double bill
- Audio files should be deleted locally after successful sync/save

## Security Rules

- No OpenAI key in iOS app
- AI calls happen only in Edge Functions
- Supabase RLS on all user data tables
- Store only required data; keep audio retention short

