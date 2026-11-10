-- AI 3D models of catalog products (Stability AI SPAR3D, $0.04 each).
-- Each product's model is made once, saved in Storage, and shared.

-- Usage rows can now be 3D models too.
alter table public.usage_events drop constraint if exists usage_events_kind_check;
alter table public.usage_events add constraint usage_events_kind_check
  check (kind in ('image', 'label', 'scan', 'model3d'));

-- Kill switch and limits. Off until you add the Stability key and turn it
-- on. Hard cap: $5 a month for everyone (about 125 models at 4 cents).
insert into public.app_config (key, value) values
  ('model_3d', '{"enabled": false, "per_day": 5, "per_month": 20, "monthly_budget_cents": 500}')
on conflict (key) do nothing;

-- Which products already have a model.
create table public.product_models (
  product_id text primary key,
  path text not null,
  image_url text,
  created_at timestamptz not null default now()
);

alter table public.product_models enable row level security;
-- No policies: only Edge Functions (service role) read or write it.
grant all on public.product_models to service_role;

-- The model files. Public to read (they're pictures of public products),
-- written only by the generate-3d function. 20 MB per file at most.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-models', 'product-models', true, 20971520, array['model/gltf-binary'])
on conflict (id) do nothing;
