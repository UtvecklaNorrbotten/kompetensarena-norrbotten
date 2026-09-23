-- Övergripande register för datakällor och senaste lyckade hämtning.
-- Används både av SCB, Arbetsförmedlingen och framtida källor.

create table if not exists public.data_sources (
  id text primary key,
  provider text not null,
  name text not null,
  source_url text,
  cadence text,
  check_from_day_of_month integer check (
    check_from_day_of_month is null
    or check_from_day_of_month between 1 and 31
  ),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.data_source_state (
  source_id text primary key references public.data_sources(id) on delete cascade,
  latest_available_period text,
  latest_successful_period text,
  last_checked_at timestamptz,
  last_successful_at timestamptz,
  last_status text not null default 'never'
    check (last_status in ('never', 'waiting', 'ready', 'no_change', 'succeeded', 'failed')),
  last_error text,
  details jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.data_source_runs
  add column if not exists source_id text references public.data_sources(id) on delete set null,
  add column if not exists source_period text,
  add column if not exists details jsonb;

grant select on public.data_sources to authenticated;
grant select on public.data_source_state to authenticated;
grant all on public.data_sources to service_role;
grant all on public.data_source_state to service_role;

alter table public.data_sources enable row level security;
alter table public.data_source_state enable row level security;

drop policy if exists "Datakällor för admin" on public.data_sources;
create policy "Datakällor för admin" on public.data_sources
  for select to authenticated
  using (public.has_role(auth.uid(), 'admin'));

drop policy if exists "Datakällestatus för admin" on public.data_source_state;
create policy "Datakällestatus för admin" on public.data_source_state
  for select to authenticated
  using (public.has_role(auth.uid(), 'admin'));

insert into public.data_sources (
  id, provider, name, source_url, cadence, check_from_day_of_month, active
) values
  (
    'scb-tab6929',
    'SCB',
    'E3 – TAB6929',
    'https://statistikdatabasen.scb.se/',
    'metadata',
    null,
    true
  ),
  (
    'af-monthly',
    'Arbetsförmedlingen',
    'Arbetsförmedlingens månadsfiler',
    'https://arbetsformedlingen.se/statistik/sok-statistik/tidigare-statistik-tidsserier',
    'monthly',
    23,
    true
  )
on conflict (id) do update set
  provider = excluded.provider,
  name = excluded.name,
  source_url = excluded.source_url,
  cadence = excluded.cadence,
  check_from_day_of_month = excluded.check_from_day_of_month,
  active = excluded.active;

insert into public.data_source_state (source_id)
values ('scb-tab6929'), ('af-monthly')
on conflict (source_id) do nothing;
