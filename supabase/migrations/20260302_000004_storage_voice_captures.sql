-- Provision private storage bucket and RLS policies for voice capture uploads.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'voice-captures',
  'voice-captures',
  false,
  15728640,
  array[
    'audio/mp4',
    'audio/m4a',
    'audio/aac',
    'audio/mpeg',
    'audio/wav',
    'application/octet-stream'
  ]
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "voice_captures_select_own" on storage.objects;
create policy "voice_captures_select_own" on storage.objects
for select to authenticated
using (
  bucket_id = 'voice-captures'
  and owner = auth.uid()
);

drop policy if exists "voice_captures_insert_own" on storage.objects;
create policy "voice_captures_insert_own" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'voice-captures'
  and owner = auth.uid()
  and split_part(name, '/', 1) = auth.uid()::text
);

drop policy if exists "voice_captures_update_own" on storage.objects;
create policy "voice_captures_update_own" on storage.objects
for update to authenticated
using (
  bucket_id = 'voice-captures'
  and owner = auth.uid()
  and split_part(name, '/', 1) = auth.uid()::text
)
with check (
  bucket_id = 'voice-captures'
  and owner = auth.uid()
  and split_part(name, '/', 1) = auth.uid()::text
);

drop policy if exists "voice_captures_delete_own" on storage.objects;
create policy "voice_captures_delete_own" on storage.objects
for delete to authenticated
using (
  bucket_id = 'voice-captures'
  and owner = auth.uid()
  and split_part(name, '/', 1) = auth.uid()::text
);
