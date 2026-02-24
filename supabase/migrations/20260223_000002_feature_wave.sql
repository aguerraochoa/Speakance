-- Speakance feature wave: custom category hints, trips, payment methods, expense links

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
  status text not null default 'planned' check (status in ('planned','active','completed')),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.payment_methods (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  method_type text not null default 'other' check (method_type in ('credit_card','debit_card','cash','apple_pay','bank_transfer','other')),
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

alter table public.expenses
  add column if not exists category_id uuid references public.categories(id) on delete set null,
  add column if not exists trip_id uuid references public.trips(id) on delete set null,
  add column if not exists trip_name text,
  add column if not exists payment_method_id uuid references public.payment_methods(id) on delete set null,
  add column if not exists payment_method_name text;

create index if not exists expenses_user_trip_id_idx on public.expenses (user_id, trip_id);
create index if not exists expenses_user_payment_method_id_idx on public.expenses (user_id, payment_method_id);
create index if not exists category_hints_user_category_idx on public.category_hints (user_id, category_id);
create index if not exists category_hints_user_phrase_idx on public.category_hints (user_id, normalized_phrase);
create index if not exists trips_user_created_at_idx on public.trips (user_id, created_at desc);
create index if not exists payment_methods_user_created_at_idx on public.payment_methods (user_id, created_at desc);
create index if not exists payment_method_aliases_user_phrase_idx on public.payment_method_aliases (user_id, normalized_phrase);

drop trigger if exists set_trips_updated_at on public.trips;
create trigger set_trips_updated_at
before update on public.trips
for each row execute function public.set_updated_at();

drop trigger if exists set_payment_methods_updated_at on public.payment_methods;
create trigger set_payment_methods_updated_at
before update on public.payment_methods
for each row execute function public.set_updated_at();

alter table public.category_hints enable row level security;
alter table public.trips enable row level security;
alter table public.payment_methods enable row level security;
alter table public.payment_method_aliases enable row level security;

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
