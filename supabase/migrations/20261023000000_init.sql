-- Interior Design app: the whole database, set up in one go.
--
-- Security model, in short:
--   * Row level security (RLS) is on for every table.
--   * People can read and change only their own profile, and read only
--     their own usage. Nobody can write usage, spend, cache, or config
--     rows from the app: only our Edge Functions can, using the service
--     role key, which never leaves Supabase.

-- ---------------------------------------------------------------------
-- Profiles: one row per signed-in person.
-- ---------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  email text,
  sign_in_method text,               -- 'email', 'google', or 'apple'
  preferences jsonb not null default '{}'::jsonb,  -- styles, materials, minimum rating, units
  budget numeric(10, 2),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Read own profile" on public.profiles
  for select using (auth.uid() = id);
create policy "Update own profile" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- A new sign-up gets a profile automatically.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, email, display_name, sign_in_method)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
    coalesce(new.raw_app_meta_data ->> 'provider', 'email')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- Usage: every paid action (image, label, room scan), one row each.
-- Counting rows gives "today" and "this month".
-- ---------------------------------------------------------------------
create table public.usage_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('image', 'label', 'scan')),
  cost_cents integer not null default 0,
  created_at timestamptz not null default now()
);

create index usage_events_user_time on public.usage_events (user_id, kind, created_at);

alter table public.usage_events enable row level security;

create policy "Read own usage" on public.usage_events
  for select using (auth.uid() = user_id);
-- No insert/update/delete policies: only Edge Functions write here.

-- ---------------------------------------------------------------------
-- Settings the backend reads, changeable in the dashboard without
-- redeploying. Not readable from the app.
-- ---------------------------------------------------------------------
create table public.app_config (
  key text primary key,
  value jsonb not null
);

alter table public.app_config enable row level security;

insert into public.app_config (key, value) values
  -- Kill switch and limits for AI images. Hard cap: $5 a month for everyone.
  ('image_generation', '{"enabled": false, "per_day": 3, "per_month": 10, "monthly_budget_cents": 500}'),
  -- Channel3's free tier is 1,000 credits a month; stop at 900 to be safe.
  ('catalog', '{"monthly_search_limit": 900, "searches_per_10_min": 30}'),
  ('labeling', '{"enabled": false, "monthly_budget_cents": 0}'),   -- not used in v1
  ('room_scan', '{"enabled": false, "monthly_budget_cents": 0}');  -- not used in v1

-- ---------------------------------------------------------------------
-- Spend: a running total per service per month, with a hard stop.
-- ---------------------------------------------------------------------
create table public.spend_ledger (
  month date not null,               -- first day of the month
  service text not null,             -- 'channel3', 'image', 'label', 'scan'
  units integer not null default 0,  -- searches, images, ...
  cents integer not null default 0,
  primary key (month, service)
);

alter table public.spend_ledger enable row level security;

-- Adds to this month's total only if it stays under both limits, in one
-- step, so two requests at once can never both slip past the limit.
-- Returns true when the spend was allowed (and recorded).
create function public.try_spend(
  p_service text, p_units integer, p_cents integer,
  p_max_units integer, p_max_cents integer
) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  this_month date := date_trunc('month', now())::date;
  allowed boolean;
begin
  insert into public.spend_ledger (month, service) values (this_month, p_service)
  on conflict do nothing;

  update public.spend_ledger
     set units = units + p_units, cents = cents + p_cents
   where month = this_month and service = p_service
     and (p_max_units is null or units + p_units <= p_max_units)
     and (p_max_cents is null or cents + p_cents <= p_max_cents)
  returning true into allowed;

  return coalesce(allowed, false);
end;
$$;

-- ---------------------------------------------------------------------
-- Rate limits: how many requests one person or device made recently.
-- ---------------------------------------------------------------------
create table public.rate_limits (
  bucket text not null,              -- 'user:<id>' or 'device:<id>'
  window_start timestamptz not null,
  count integer not null default 0,
  primary key (bucket, window_start)
);

alter table public.rate_limits enable row level security;

-- Counts one request; returns false once the window's limit is reached.
create function public.hit_rate_limit(p_bucket text, p_max integer, p_window_seconds integer)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  win timestamptz := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);
  current_count integer;
begin
  insert into public.rate_limits (bucket, window_start, count) values (p_bucket, win, 1)
  on conflict (bucket, window_start) do update set count = public.rate_limits.count + 1
  returning count into current_count;

  -- Old windows are cleared now and then.
  if random() < 0.01 then
    delete from public.rate_limits where window_start < now() - interval '1 day';
  end if;

  return current_count <= p_max;
end;
$$;

-- ---------------------------------------------------------------------
-- Product cache: search answers kept for a day, to save credits.
-- ---------------------------------------------------------------------
create table public.product_cache (
  key text primary key,
  response jsonb not null,
  created_at timestamptz not null default now()
);

alter table public.product_cache enable row level security;

-- Only the backend may call these helpers.
revoke execute on function public.try_spend from public, anon, authenticated;
revoke execute on function public.hit_rate_limit from public, anon, authenticated;
