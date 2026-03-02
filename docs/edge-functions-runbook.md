# Edge Functions Runbook

## Purpose

Prevent auth regressions when deploying Supabase Edge Functions, especially `parse-expense`.

## Critical Rule

`parse-expense` and `delete-account` must be deployed with `--no-verify-jwt`.

Reason: gateway JWT verification can reject valid user JWTs in this project with `401 Invalid JWT`.  
Both functions perform explicit in-function auth validation against Supabase Auth.

## Deploy Commands

Run from repo root:

```bash
cd /Users/andresguerra/Documents/Non-Work/Apps/Speakance
supabase login
supabase functions deploy parse-expense --project-ref pyramncggeecifntwlop --use-api --no-verify-jwt
supabase functions deploy delete-account --project-ref pyramncggeecifntwlop --use-api --no-verify-jwt
supabase functions list --project-ref pyramncggeecifntwlop
```

## Verification

After deploy:

1. Sign out in app.
2. Sign in again.
3. Add a text expense.
4. Confirm app log contains `parseExpense response ... status=200`.

## If You See `Invalid JWT` Again

1. Re-deploy `parse-expense` and `delete-account` with `--no-verify-jwt`.
2. Confirm project ref is `pyramncggeecifntwlop`.
3. Check app token issuer in logs:
   - `iss=https://pyramncggeecifntwlop.supabase.co/auth/v1`

## Notes

- Simulator noise like `load_eligibility_plist`, keyboard auto-layout warnings, and CoreGraphics NaN warnings are unrelated to auth rejection.
