-- Table permissions.
--
-- Newer Supabase projects don't automatically give the built-in roles access
-- to new tables, so every query from our Edge Functions failed with
-- "permission denied for table ...". Row level security (in the first
-- migration) still decides WHICH rows each person sees; these grants only
-- allow the roles to use the tables at all.

-- Edge Functions use the service role: full access to our tables.
grant usage on schema public to service_role;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
grant execute on function public.try_spend(text, integer, integer, integer, integer) to service_role;
grant execute on function public.hit_rate_limit(text, integer, integer) to service_role;

-- Signed-in people (through the app): only what row level security allows.
grant usage on schema public to authenticated;
grant select, update on public.profiles to authenticated;
grant select on public.usage_events to authenticated;

-- Guests (anon) get no direct table access; they only use Edge Functions.
