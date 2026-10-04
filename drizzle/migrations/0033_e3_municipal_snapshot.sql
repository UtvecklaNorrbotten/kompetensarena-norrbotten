-- E3 kommun: separat indikator, större fulla batchar och versionsbunden återstart.
alter table public.etl_batches drop constraint if exists etl_batches_expected_chunks_check;
alter table public.etl_batches add constraint etl_batches_expected_chunks_check
  check (expected_chunks > 0 and expected_chunks <= 10000);
alter table public.etl_batches add column if not exists import_key text;
alter table public.etl_batches drop constraint if exists etl_batches_import_key_check;
alter table public.etl_batches add constraint etl_batches_import_key_check
  check (import_key is null or import_key ~ '^[a-f0-9]{64}$');
create index if not exists etl_batches_import_key_idx on public.etl_batches (indicator_id, import_key, created_at desc)
  where import_key is not null;

insert into public.indicators
  (id, name, description, unit, styrande_kalla, source_table_id, frequency, visibility, is_example)
values
  ('e3-matchning-utbildning-kommun', 'Matchning mellan utbildning och yrke – kommun (E3)',
   'Alla kommuner, år, utbildningsgrupper och näringsgrenar. Total befolkning, sju mått inklusive D. Ingen uppdelning på kön, ålder, födelseland, utbildningsnivå eller utbildningsinriktning.',
   'Varierar per tabellinnehåll', 'TAB6929', 'TAB6929', 'Årlig', 'publik', false),
  ('e3-matchning-utbildning-kommun-etl-test', 'E3 kommun – ETL-test',
   'Teknisk kontrollindikator; inte publik.', 'Varierar per tabellinnehåll',
   'TAB6929', 'TAB6929', 'Årlig', 'admin', false)
on conflict (id) do nothing;

create or replace function public.etl_start_snapshot_batch(
  p_indicator_id text, p_source text, p_expected_chunks integer,
  p_import_key text, p_expected_rows integer default null,
  p_kalla_uppdaterad_datum date default null, p_run_id uuid default null
)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if p_import_key is null or p_import_key !~ '^[a-f0-9]{64}$' then
    raise exception 'Ogiltig importnyckel' using errcode = 'invalid_parameter_value';
  end if;
  perform pg_advisory_xact_lock(hashtext(p_indicator_id));
  if exists (select 1 from etl_batches where indicator_id = p_indicator_id
    and import_key = p_import_key and status in ('started','receiving','ready','failed')) then
    raise exception 'Samma snapshot finns redan; återuppta batchen'
      using errcode = 'invalid_parameter_value';
  end if;
  v_id := public.etl_start_batch(p_indicator_id, p_source, p_expected_chunks,
    p_expected_rows, p_kalla_uppdaterad_datum, p_run_id);
  update public.etl_batches set import_key = p_import_key where id = v_id;
  return v_id;
end $$;

create or replace function public.etl_snapshot_progress(p_batch_id uuid, p_import_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.etl_batches%rowtype; n integer; last_index integer; rows bigint;
begin
  select * into b from public.etl_batches where id = p_batch_id;
  if not found then raise exception 'Okänd batch' using errcode = 'no_data_found'; end if;
  if b.import_key is distinct from p_import_key or b.import_key is null then
    raise exception 'Importnyckeln stämmer inte' using errcode = 'invalid_parameter_value';
  end if;
  select count(*), max(chunk_index), coalesce(sum(row_count),0)
    into n, last_index, rows from public.etl_batch_chunks where batch_id = p_batch_id;
  if n <> b.received_chunks or rows <> b.received_rows
     or (n > 0 and last_index <> n - 1) then
    raise exception 'Sparade chunkar är inte en sammanhängande, verifierad följd'
      using errcode = 'invalid_parameter_value';
  end if;
  return jsonb_build_object('next_chunk_index', n);
end $$;

revoke all on function public.etl_start_snapshot_batch(text,text,integer,text,integer,date,uuid)
  from public, anon, authenticated;
revoke all on function public.etl_snapshot_progress(uuid,text) from public, anon, authenticated;
grant execute on function public.etl_start_snapshot_batch(text,text,integer,text,integer,date,uuid) to service_role;
grant execute on function public.etl_snapshot_progress(uuid,text) to service_role;

notify pgrst, 'reload schema';