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
