-- Exempel: isolerad testschemamodell, aldrig körbar mot produktionsdatabasen.
create role anon;
create role authenticated;
create role service_role;
create table public.indicators (
  id text primary key, name text, description text, unit text, styrande_kalla text,
  source_table_id text, frequency text, visibility text, is_example boolean
);
create table public.etl_batches (
  id uuid primary key default gen_random_uuid(), indicator_id text, source text,
  expected_chunks integer constraint etl_batches_expected_chunks_check check (expected_chunks <= 2000),
  expected_rows integer, received_chunks integer default 0, received_rows integer default 0,
  status text default 'started', created_at timestamptz default now(),
  kalla_uppdaterad_datum date, run_id uuid
);
create table public.etl_batch_chunks (
  batch_id uuid references public.etl_batches(id), chunk_index integer check (chunk_index >= 0),
  row_count integer, primary key (batch_id, chunk_index)
);
create function public.etl_start_batch(
  p_indicator_id text, p_source text, p_expected_chunks integer,
  p_expected_rows integer default null, p_kalla_uppdaterad_datum date default null,
  p_run_id uuid default null
) returns uuid language plpgsql as $$
declare v_id uuid;
begin
  insert into public.etl_batches(indicator_id,source,expected_chunks,expected_rows,kalla_uppdaterad_datum,run_id)
  values(p_indicator_id,p_source,p_expected_chunks,p_expected_rows,p_kalla_uppdaterad_datum,p_run_id)
  returning id into v_id;
  return v_id;
end $$;

create type public.geo_level as enum ('riket','län','kommun');
create table public.indicator_active_batches (indicator_id text primary key, active_batch_id uuid);
create table public.observations (batch_id uuid, indicator_id text, geo_code text, period text,
  value double precision, dimensions jsonb);
create table public.agg_e3_matchning (
  geo_code text, geo_level public.geo_level, period text, utbildning_code text,
  utbildning_label text, sni_code text, sni_label text,
  helt double precision, delvis double precision, inte double precision,
  saknas double precision, totalt double precision,
  primary key (geo_code,period,utbildning_code,sni_code)
);
create table public.agg_refresh_state (name text primary key, source_marker text);
create function public.agg_mark(text,text,integer,timestamptz,text) returns void
language sql as $$
  insert into public.agg_refresh_state(name,source_marker) values($1,$5)
  on conflict(name) do update set source_marker=excluded.source_marker;
$$;
