-- Align system/default category bank with current app taxonomy.
-- Current bank:
-- Food, Groceries, Transport, Shopping, Utilities, Entertainment, Subscriptions, Other

-- Rename legacy "Bills" system category to "Utilities" (preserve existing IDs/references).
update public.categories
set
  name = 'Utilities',
  system_key = 'utilities',
  color_hex = '#EF4444',
  is_default = true
where user_id is null
  and lower(name) = 'bills';

-- Normalize core system category metadata/colors.
update public.categories set system_key = 'food', color_hex = '#F97316', is_default = true
where user_id is null and lower(name) = 'food';

update public.categories set system_key = 'groceries', color_hex = '#22C55E', is_default = true
where user_id is null and lower(name) = 'groceries';

update public.categories set system_key = 'transport', color_hex = '#0EA5E9', is_default = true
where user_id is null and lower(name) = 'transport';

update public.categories set system_key = 'shopping', color_hex = '#EC4899', is_default = true
where user_id is null and lower(name) = 'shopping';

update public.categories set system_key = 'entertainment', color_hex = '#8B5CF6', is_default = true
where user_id is null and lower(name) = 'entertainment';

update public.categories set system_key = 'subscriptions', color_hex = '#6366F1', is_default = true
where user_id is null and lower(name) = 'subscriptions';

update public.categories set system_key = 'other', color_hex = '#64748B', is_default = true
where user_id is null and lower(name) = 'other';

-- Insert missing system categories from the current bank.
insert into public.categories (user_id, name, color_hex, system_key, is_default)
select null, 'Groceries', '#22C55E', 'groceries', true
where not exists (
  select 1 from public.categories c
  where c.user_id is null and lower(c.name) = 'groceries'
);

insert into public.categories (user_id, name, color_hex, system_key, is_default)
select null, 'Subscriptions', '#6366F1', 'subscriptions', true
where not exists (
  select 1 from public.categories c
  where c.user_id is null and lower(c.name) = 'subscriptions'
);

insert into public.categories (user_id, name, color_hex, system_key, is_default)
select null, 'Utilities', '#EF4444', 'utilities', true
where not exists (
  select 1 from public.categories c
  where c.user_id is null and lower(c.name) = 'utilities'
);

