-- Kompetensarena Norrbotten: grundläggande datamodell enligt godkänd arkitekturplan v3

-- Enum: geografisk nivå
create type public.geo_level as enum ('riket', 'län', 'kommun');

-- Enum: synlighetsnivå för data (publik / inloggad / admin)
create type public.visibility_level as enum ('publik', 'inloggad', 'admin');

-- Enum: status för ETL-körningar
create type public.run_status as enum ('started', 'no_change', 'succeeded', 'failed');

-- Enum: användarroller (lagras i separat tabell, aldrig på profilen)
create type public.app_role as enum ('admin', 'editor', 'registered');

-- Geografier
create table public.geographies (
  code text primary key,
  name text not null,
  level public.geo_level not null,
  parent_code text references public.geographies(code)
);
grant select on public.geographies to anon;
grant select on public.geographies to authenticated;
grant all on public.geographies to service_role;
alter table public.geographies enable row level security;
create policy "Geografier är publika" on public.geographies for select to anon, authenticated using (true);

-- Indikatorer
create table public.indicators (
  id text primary key,
  name text not null,
  description text not null default '',
  unit text not null default '',
  styrande_kalla text not null,
  source_table_id text,
  frequency text,
  visibility public.visibility_level not null default 'publik',
  is_example boolean not null default false,
  created_at timestamptz not null default now()
);
grant select on public.indicators to anon;
grant select on public.indicators to authenticated;
grant all on public.indicators to service_role;
alter table public.indicators enable row level security;

-- Observationer (tidsseriepunkter)
create table public.observations (
  id uuid primary key default gen_random_uuid(),
  indicator_id text not null references public.indicators(id) on delete cascade,
  geo_code text not null references public.geographies(code),
  period text not null,
  value double precision,
  dimensions jsonb not null default '{}'::jsonb,
  unique (indicator_id, geo_code, period, dimensions)
);
grant select on public.observations to anon;
grant select on public.observations to authenticated;
grant all on public.observations to service_role;
alter table public.observations enable row level security;

-- Indikatormetadata enligt RUS-konventioner
create table public.indicator_metadata (
  indicator_id text primary key references public.indicators(id) on delete cascade,
  kalla text not null,
  styrande_kalla text not null,
  kalla_uppdaterad_datum date,
  hamtad_datum date,
  tillganglighetsdatum date generated always as (coalesce(kalla_uppdaterad_datum, hamtad_datum)) stored,
  period text,
  note text,
  updated_at timestamptz not null default now()
);
grant select on public.indicator_metadata to anon;
grant select on public.indicator_metadata to authenticated;
grant all on public.indicator_metadata to service_role;
alter table public.indicator_metadata enable row level security;

-- Körningslogg för ETL
create table public.data_source_runs (
  id uuid primary key default gen_random_uuid(),
  source text not null,
  indicator_id text references public.indicators(id) on delete set null,
  status public.run_status not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  rows_affected integer,
  error_message text
);
grant select on public.data_source_runs to authenticated;
grant all on public.data_source_runs to service_role;
alter table public.data_source_runs enable row level security;

-- Uppladdade dokument (filreferens till Storage)
create table public.documents (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  doc_type text,
  storage_path text not null,
  indicator_id text references public.indicators(id) on delete set null,
  uploaded_by uuid,
  visibility public.visibility_level not null default 'publik',
  created_at timestamptz not null default now()
);
grant select on public.documents to anon;
grant select on public.documents to authenticated;
grant all on public.documents to service_role;
alter table public.documents enable row level security;

-- Användarroller (separat tabell)
create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  role public.app_role not null,
  unique (user_id, role)
);
grant select on public.user_roles to authenticated;
grant all on public.user_roles to service_role;
alter table public.user_roles enable row level security;

-- Säkerhetsfunktion för rollkontroll (security definer, undviker rekursiv RLS)
create or replace function public.has_role(_user_id uuid, _role public.app_role)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = _user_id and role = _role
  )
$$;

-- RLS-policies med tre synlighetsnivåer
create policy "Publika indikatorer läsbara av alla" on public.indicators for select to anon
  using (visibility = 'publik');
create policy "Inloggade ser publik och inloggad nivå" on public.indicators for select to authenticated
  using (visibility in ('publik', 'inloggad') or public.has_role(auth.uid(), 'admin'));

create policy "Publika observationer läsbara av alla" on public.observations for select to anon
  using (exists (select 1 from public.indicators i where i.id = indicator_id and i.visibility = 'publik'));
create policy "Inloggade ser observationer enligt nivå" on public.observations for select to authenticated
  using (exists (select 1 from public.indicators i where i.id = indicator_id
    and (i.visibility in ('publik', 'inloggad') or public.has_role(auth.uid(), 'admin'))));

create policy "Metadata följer indikatorns nivå (anon)" on public.indicator_metadata for select to anon
  using (exists (select 1 from public.indicators i where i.id = indicator_id and i.visibility = 'publik'));
create policy "Metadata följer indikatorns nivå (inloggad)" on public.indicator_metadata for select to authenticated
  using (exists (select 1 from public.indicators i where i.id = indicator_id
    and (i.visibility in ('publik', 'inloggad') or public.has_role(auth.uid(), 'admin'))));

create policy "Körningslogg för admin" on public.data_source_runs for select to authenticated
  using (public.has_role(auth.uid(), 'admin'));

create policy "Publika dokument läsbara av alla" on public.documents for select to anon
  using (visibility = 'publik');
create policy "Inloggade ser dokument enligt nivå" on public.documents for select to authenticated
  using (visibility in ('publik', 'inloggad') or public.has_role(auth.uid(), 'admin'));

create policy "Användare ser egna roller" on public.user_roles for select to authenticated
  using (auth.uid() = user_id);

-- Atomisk publicering av en enskild indikator (anropas av ETL via server route).
-- SECURITY DEFINER: funktionen får ersätta observationsdata, men endast inom sin fasta logik.
-- EXECUTE återkallas från PUBLIC och ges bara till service_role (appen verifierar anroparen).
create or replace function public.publish_indicator(
  p_indicator_id text,
  p_observations jsonb,
  p_kalla_uppdaterad_datum date default null,
  p_rows_affected integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
begin
  -- Indikatorn måste finnas
  if not exists (select 1 from public.indicators where id = p_indicator_id) then
    raise exception 'Indikator % finns inte', p_indicator_id;
  end if;

  -- Obligatoriska fält i varje observationspost
  if exists (
    select 1 from jsonb_array_elements(p_observations) o
    where not (o ? 'geo_code' and o ? 'period')
  ) then
    raise exception 'Varje observation måste ha geo_code och period';
  end if;

  -- Advisory lock per indikator: förhindrar samtidiga publiceringar
  perform pg_advisory_xact_lock(hashtext(p_indicator_id));

  -- Ersätt observationer för just denna indikator (allt eller inget i transaktionen)
  delete from public.observations where indicator_id = p_indicator_id;

  insert into public.observations (indicator_id, geo_code, period, value, dimensions)
  select
    p_indicator_id,
    o->>'geo_code',
    o->>'period',
    (o->>'value')::double precision,
    coalesce(o->'dimensions', '{}'::jsonb)
  from jsonb_array_elements(p_observations) o;
  get diagnostics v_count = row_count;

  -- Uppdatera metadata (RUS-fält)
  insert into public.indicator_metadata (indicator_id, kalla, styrande_kalla, kalla_uppdaterad_datum, hamtad_datum, updated_at)
  select i.styrande_kalla, i.styrande_kalla, p_kalla_uppdaterad_datum, current_date, now()
  from public.indicators i where i.id = p_indicator_id
  on conflict (indicator_id) do update set
    kalla_uppdaterad_datum = coalesce(excluded.kalla_uppdaterad_datum, public.indicator_metadata.kalla_uppdaterad_datum),
    hamtad_datum = current_date,
    updated_at = now();

  return jsonb_build_object('indicator_id', p_indicator_id, 'rows', v_count);
end;
$$;

revoke execute on function public.publish_indicator(text, jsonb, date, integer) from public, anon, authenticated;
grant execute on function public.publish_indicator(text, jsonb, date, integer) to service_role;

-- Seed: Norrbottens län + exempelindikatorn (flyttad från lokal exempelfil)
insert into public.geographies (code, name, level) values
  ('25', 'Norrbottens län', 'län');

insert into public.indicators (id, name, description, unit, styrande_kalla, visibility, is_example) values
  ('exempel-arbetsloshet', 'Arbetslöshet (exempel)',
   'Andel av befolkningen 16–64 år som är inskriven som arbetslös. Serien är påhittad och används endast för att visa hur en indikator presenteras.',
   'procent', 'Exempelkälla', 'publik', true);

insert into public.indicator_metadata (indicator_id, kalla, styrande_kalla, kalla_uppdaterad_datum, hamtad_datum, period) values
  ('exempel-arbetsloshet', 'Exempelkälla', 'Exempelkälla', '2026-09-01', '2026-09-01', '2017–2026');

insert into public.observations (indicator_id, geo_code, period, value) values
  ('exempel-arbetsloshet', '25', '2017', 6.8),
  ('exempel-arbetsloshet', '25', '2018', 6.5),
  ('exempel-arbetsloshet', '25', '2019', 6.4),
  ('exempel-arbetsloshet', '25', '2020', 7.9),
  ('exempel-arbetsloshet', '25', '2021', 7.2),
  ('exempel-arbetsloshet', '25', '2022', 6.3),
  ('exempel-arbetsloshet', '25', '2023', 6.1),
  ('exempel-arbetsloshet', '25', '2024', 5.9),
  ('exempel-arbetsloshet', '25', '2025', 5.7),
  ('exempel-arbetsloshet', '25', '2026', 5.6);
