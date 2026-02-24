# API Contracts (V1 Draft)

## Edge Function: `parse-expense`

### Purpose

Accept a text entry or voice metadata, parse it into a structured expense, enforce usage limits, and save idempotently.

### Request (JSON, V1 draft)

```json
{
  "client_expense_id": "uuid",
  "source": "voice",
  "captured_at_device": "2026-02-22T18:30:00Z",
  "timezone": "America/Mexico_City",
  "audio_duration_seconds": 8,
  "raw_text": "I spent 250 pesos on tacos with friends",
  "currency_hint": "MXN",
  "allow_auto_save": false
}
```

Notes:

- `raw_text` may be omitted for voice if server performs STT from uploaded audio (future endpoint variant).
- V1 scaffold uses text payloads first for fast iteration.

### Response (Success)

```json
{
  "status": "needs_review",
  "expense": {
    "id": "server-uuid",
    "client_expense_id": "uuid",
    "amount": 250,
    "currency": "MXN",
    "category": "Food",
    "description": "tacos with friends",
    "merchant": null,
    "expense_date": "2026-02-22",
    "source": "voice",
    "parse_status": "auto"
  },
  "parse": {
    "confidence": 0.84,
    "raw_text": "I spent 250 pesos on tacos with friends",
    "needs_review": true
  },
  "usage": {
    "daily_voice_used": 14,
    "daily_voice_limit": 50
  }
}
```

### Response Statuses

- `saved`
- `needs_review`
- `queued` (client-side concept, not usually returned by server)
- `rejected_limit`
- `error`

### Validation Rules (V1)

- `audio_duration_seconds <= 15` for voice
- Voice submissions limited per user/day (default: `50`)
- `amount > 0`
- `currency` in allowed set (`USD`, `MXN`, etc.)
- `captured_at_device` required for offline-friendly accounting

