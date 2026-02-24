-- Speakance V1 initial schema
-- Apply in Supabase SQL editor or via supabase migrations.

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

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  client_expense_id uuid not null,
  amount numeric(12,2) not null check (amount > 0),
  currency text not null,
  category text not null,
  description text,
  merchant text,
  expense_date date not null,
  captured_at_device timestamptz not null,
  synced_at timestamptz,
  source text not null check (source in ('voice','text')),
  parse_status text not null default 'auto' check (parse_status in ('auto','edited','failed')),
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
  event_type text not null check (event_type in ('voice_parse','text_parse')),
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
create index if not exists ai_usage_events_user_created_at_idx on public.ai_usage_events (user_id, created_at desc);

drop trigger if exists set_profiles_updated_at on public.profiles;
create trigger set_profiles_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists set_expenses_updated_at on public.expenses;
create trigger set_expenses_updated_at
before update on public.expenses
for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
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

insert into public.categories (user_id, name, color_hex, system_key, is_default)
values
  (null, 'Food', '#F97316', 'food', true),
  (null, 'Transport', '#0EA5E9', 'transport', true),
  (null, 'Entertainment', '#8B5CF6', 'entertainment', true),
  (null, 'Shopping', '#EC4899', 'shopping', true),
  (null, 'Bills', '#EF4444', 'bills', true),
  (null, 'Other', '#64748B', 'other', true)
on conflict do nothing;

