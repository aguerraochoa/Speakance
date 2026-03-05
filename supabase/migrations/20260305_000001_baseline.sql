-- Speakance baseline schema (clean restart)

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  default_currency text not null default 'USD',
  timezone text not null default 'UTC',
  parsing_language text check (parsing_language in ('auto', 'english', 'spanish')),
  daily_voice_limit integer not null default 50 check (daily_voice_limit > 0),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  name text not null,
  color_hex text,
  system_key text,
  is_default boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  unique (user_id, name)
);

create table if not exists public.category_hints (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete cascade,
  phrase text not null,
  normalized_phrase text not null,
  created_at timestamptz not null default timezone('utc', now()),
  unique (user_id, category_id, normalized_phrase)
);

create table if not exists public.trips (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  destination text,
  start_date date not null,
  end_date date,
  base_currency text,
  status text not null default 'planned' check (status in ('planned', 'active', 'completed')),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  method_type text not null default 'other' check (method_type in ('credit_card', 'debit_card', 'cash', 'apple_pay', 'bank_transfer', 'other')),
  network text,
  last4 text,
  color_hex text,
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (user_id, name)
);

create table if not exists public.payment_method_aliases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  payment_method_id uuid not null references public.payment_methods(id) on delete cascade,
  phrase text not null,
  normalized_phrase text not null,
  created_at timestamptz not null default timezone('utc', now()),
  unique (user_id, payment_method_id, normalized_phrase)
);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  client_expense_id uuid not null,
  amount numeric(12,2) not null check (amount > 0),
  currency text not null,
  category text not null,
  category_id uuid references public.categories(id) on delete set null,
  description text,
  merchant text,
  trip_id uuid references public.trips(id) on delete set null,
  trip_name text,
  payment_method_id uuid references public.payment_methods(id) on delete set null,
  payment_method_name text,
  expense_date date not null,
  captured_at_device timestamptz not null,
  synced_at timestamptz,
  source text not null check (source in ('voice', 'text')),
  parse_status text not null default 'auto' check (parse_status in ('auto', 'needs_review', 'edited', 'failed')),
  parse_confidence numeric(4,3),
  raw_text text,
  audio_duration_seconds integer check (audio_duration_seconds is null or audio_duration_seconds between 1 and 15),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (user_id, client_expense_id)
);

create table if not exists public.ai_usage_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  client_expense_id uuid,
  event_type text not null check (event_type in ('voice_parse', 'text_parse')),
  provider text not null default 'openai',
  model text,
  input_tokens integer,
  output_tokens integer,
  audio_seconds integer,
  estimated_cost_usd numeric(10,6),
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists expenses_user_expense_date_idx on public.expenses (user_id, expense_date desc);
create index if not exists expenses_user_created_at_idx on public.expenses (user_id, created_at desc);
create index if not exists expenses_user_trip_id_idx on public.expenses (user_id, trip_id);
create index if not exists expenses_user_payment_method_id_idx on public.expenses (user_id, payment_method_id);
create index if not exists category_hints_user_category_idx on public.category_hints (user_id, category_id);
create index if not exists category_hints_user_phrase_idx on public.category_hints (user_id, normalized_phrase);
create index if not exists trips_user_created_at_idx on public.trips (user_id, created_at desc);
create index if not exists payment_methods_user_created_at_idx on public.payment_methods (user_id, created_at desc);
create index if not exists payment_method_aliases_user_phrase_idx on public.payment_method_aliases (user_id, normalized_phrase);
create index if not exists ai_usage_events_user_created_at_idx on public.ai_usage_events (user_id, created_at desc);

create unique index if not exists categories_system_name_unique_idx
  on public.categories (lower(name))
  where user_id is null;

create unique index if not exists ai_usage_events_user_client_event_unique_idx
  on public.ai_usage_events (user_id, client_expense_id, event_type)
  where client_expense_id is not null;

drop trigger if exists set_profiles_updated_at on public.profiles;
create trigger set_profiles_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists set_expenses_updated_at on public.expenses;
create trigger set_expenses_updated_at
before update on public.expenses
for each row execute function public.set_updated_at();

drop trigger if exists set_trips_updated_at on public.trips;
create trigger set_trips_updated_at
before update on public.trips
for each row execute function public.set_updated_at();

drop trigger if exists set_payment_methods_updated_at on public.payment_methods;
create trigger set_payment_methods_updated_at
before update on public.payment_methods
for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.category_hints enable row level security;
alter table public.trips enable row level security;
alter table public.payment_methods enable row level security;
alter table public.payment_method_aliases enable row level security;
alter table public.expenses enable row level security;
alter table public.ai_usage_events enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
for select using (auth.uid() = id);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
for insert with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
for update using (auth.uid() = id);

drop policy if exists "categories_select_own_or_default" on public.categories;
create policy "categories_select_own_or_default" on public.categories
for select using (user_id is null or user_id = auth.uid());

drop policy if exists "categories_manage_own" on public.categories;
create policy "categories_manage_own" on public.categories
for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "category_hints_select_own" on public.category_hints;
create policy "category_hints_select_own" on public.category_hints
for select using (user_id = auth.uid());

drop policy if exists "category_hints_manage_own" on public.category_hints;
create policy "category_hints_manage_own" on public.category_hints
for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "trips_select_own" on public.trips;
create policy "trips_select_own" on public.trips
for select using (user_id = auth.uid());

drop policy if exists "trips_manage_own" on public.trips;
create policy "trips_manage_own" on public.trips
for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "payment_methods_select_own" on public.payment_methods;
create policy "payment_methods_select_own" on public.payment_methods
for select using (user_id = auth.uid());

drop policy if exists "payment_methods_manage_own" on public.payment_methods;
create policy "payment_methods_manage_own" on public.payment_methods
for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "payment_method_aliases_select_own" on public.payment_method_aliases;
create policy "payment_method_aliases_select_own" on public.payment_method_aliases
for select using (user_id = auth.uid());

drop policy if exists "payment_method_aliases_manage_own" on public.payment_method_aliases;
create policy "payment_method_aliases_manage_own" on public.payment_method_aliases
for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "expenses_select_own" on public.expenses;
create policy "expenses_select_own" on public.expenses
for select using (user_id = auth.uid());

drop policy if exists "expenses_insert_own" on public.expenses;
create policy "expenses_insert_own" on public.expenses
for insert with check (user_id = auth.uid());

drop policy if exists "expenses_update_own" on public.expenses;
create policy "expenses_update_own" on public.expenses
for update using (user_id = auth.uid());

drop policy if exists "expenses_delete_own" on public.expenses;
create policy "expenses_delete_own" on public.expenses
for delete using (user_id = auth.uid());

drop policy if exists "ai_usage_events_select_own" on public.ai_usage_events;
create policy "ai_usage_events_select_own" on public.ai_usage_events
for select using (user_id = auth.uid());

drop policy if exists "ai_usage_events_insert_own" on public.ai_usage_events;
create policy "ai_usage_events_insert_own" on public.ai_usage_events
for insert with check (user_id = auth.uid());

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

insert into public.categories (user_id, name, color_hex, system_key, is_default)
values
  (null, 'Food', '#F97316', 'food', true),
  (null, 'Groceries', '#22C55E', 'groceries', true),
  (null, 'Transport', '#0EA5E9', 'transport', true),
  (null, 'Shopping', '#EC4899', 'shopping', true),
  (null, 'Utilities', '#EF4444', 'utilities', true),
  (null, 'Entertainment', '#8B5CF6', 'entertainment', true),
  (null, 'Subscriptions', '#6366F1', 'subscriptions', true),
  (null, 'Other', '#64748B', 'other', true)
on conflict do nothing;
