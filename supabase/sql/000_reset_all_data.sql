-- WARNING: destructive reset for non-production environments.
-- This wipes Speakance app data, storage objects, and auth users.
-- Run in Supabase SQL Editor as project owner/service role.

begin;

-- Storage cleanup must be done via Storage API/UI.
-- Direct DELETE on storage.objects is blocked by Supabase.
-- Optional manual cleanup in dashboard:
--   Storage -> voice-captures -> Empty bucket / Delete bucket.

-- Remove all app rows explicitly (safe even if auth cascade handles most of it).
delete from public.ai_usage_events;
delete from public.expenses;
delete from public.payment_method_aliases;
delete from public.payment_methods;
delete from public.category_hints;
delete from public.trips;
delete from public.profiles;
delete from public.categories;

-- Remove all auth users and identities.
delete from auth.identities;
delete from auth.sessions;
delete from auth.refresh_tokens;
delete from auth.users;

commit;
