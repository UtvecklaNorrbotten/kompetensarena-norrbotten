-- Chunkad ETL-import med staging och atomisk finalisering.
-- Komplement till publish_indicator för stora dataset (t.ex. SCB TAB6929/E3).

create type public.etl_batch_status as enum ('started', 'receiving', 'ready', 'succeeded', 'failed');

-- Batchregister (staging-huvud)
create table public.etl_batches (
  id uuid primary key default gen_random_uuid(),
  indicator_id text not null references public.indicators(id) on delete cascade,
  source text not null,
  kalla_uppdaterad_datum date,
  expected_chunks integer not null check (expected_chunks > 0 and expected_chunks <= 1000),
  received_chunks integer not null default 0,
  expected_rows integer check (expected_rows is null or expected_rows >= 0),
  received_rows integer not null default 0,
  status public.etl_batch_status not null default 'started',
  run_id uuid references public.data_source_runs(id) on delete set null,
  error_message text,
  created_at timestamptz not null default now(),
  last_activity_at timestamptz not null default now()
);

-- Stagingchunkar (rådata i väntan på finalisering)
create table public.etl_batch_chunks (
  batch_id uuid not null references public.etl_batches(id) on delete cascade,
  chunk_index integer not null check (chunk_index >= 0),
  row_count integer not null check (row_count >= 0),
  checksum text not null,
  observations jsonb not null,
  created_at timestamptz not null default now(),
  primary key (batch_id, chunk_index)
);

create index etl_batches_status_idx on public.etl_batches (status, last_activity_at);

-- Stagingdata är inte läsbar för frontend eller vanliga användare:
-- inga grants till anon/authenticated, RLS på utan policies.
grant all on public.etl_batches to service_role;
grant all on public.etl_batch_chunks to service_role;
alter table public.etl_batches enable row level security;
alter table public.etl_batch_chunks enable row level security;

-- Starta batch
create or replace function public.etl_start_batch(
  p_indicator_id text,
  p_source text,
  p_expected_chunks integer,
  p_expected_rows integer default null,
  p_kalla_uppdaterad_datum date default null,
  p_run_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not exists (select 1 from public.indicators where id = p_indicator_id) then
    raise exception 'Indikator % finns inte', p_indicator_id using errcode = 'no_data_found';
  end if;

  insert into public.etl_batches (indicator_id, source, kalla_uppdaterad_datum, expected_chunks, expected_rows, status, run_id)
  values (p_indicator_id, p_source, p_kalla_uppdaterad_datum, p_expected_chunks, p_expected_rows, 'started', p_run_id)
  returning id into v_id;

  return v_id;
end;
$$;

-- Ta emot en chunk (strikt kontroll: indikator, index, dubbletter, geografi)
create or replace function public.etl_store_chunk(
  p_batch_id uuid,
  p_indicator_id text,
  p_chunk_index integer,
  p_observations jsonb,
  p_checksum text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_batch public.etl_batches%rowtype;
  v_existing public.etl_batch_chunks%rowtype;
  v_rows integer;
  v_bad_geo text;
begin
  select * into v_batch from public.etl_batches where id = p_batch_id for update;
  if not found then
    raise exception 'Batch % finns inte', p_batch_id using errcode = 'no_data_found';
  end if;

  if v_batch.status not in ('started', 'receiving') then
    raise exception 'Batch % har status % och tar inte emot fler chunkar', p_batch_id, v_batch.status
      using errcode = 'invalid_parameter_value';
  end if;

  if v_batch.indicator_id is distinct from p_indicator_id then
    raise exception 'Chunk tillhör fel indikator (batch: %, chunk: %)', v_batch.indicator_id, p_indicator_id
      using errcode = 'invalid_parameter_value';
  end if;

  if p_chunk_index < 0 or p_chunk_index >= v_batch.expected_chunks then
    raise exception 'chunk_index % utanför intervallet 0..%', p_chunk_index, v_batch.expected_chunks - 1
      using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_observations) o
    where not (o ? 'geo_code' and o ? 'period')
  ) then
    raise exception 'Varje observation måste ha geo_code och period' using errcode = 'invalid_parameter_value';
  end if;

  select o->>'geo_code' into v_bad_geo
  from jsonb_array_elements(p_observations) o
  where not exists (select 1 from public.geographies g where g.code = o->>'geo_code')
  limit 1;
  if v_bad_geo is not null then
    raise exception 'Okänd geografi: %', v_bad_geo using errcode = 'foreign_key_violation';
  end if;

  v_rows := jsonb_array_length(p_observations);

  select * into v_existing from public.etl_batch_chunks
  where batch_id = p_batch_id and chunk_index = p_chunk_index;

  if found then
    if v_existing.checksum = p_checksum then
      update public.etl_batches set last_activity_at = now() where id = p_batch_id;
      return jsonb_build_object(
        'batch_id', p_batch_id, 'chunk_index', p_chunk_index, 'duplicate', true,
        'received_chunks', v_batch.received_chunks, 'received_rows', v_batch.received_rows,
        'status', v_batch.status
      );
    end if;
    raise exception 'Chunk % finns redan med annat innehåll', p_chunk_index
      using errcode = 'unique_violation';
  end if;

  insert into public.etl_batch_chunks (batch_id, chunk_index, row_count, checksum, observations)
  values (p_batch_id, p_chunk_index, v_rows, p_checksum, p_observations);

  update public.etl_batches
  set received_chunks = received_chunks + 1,
      received_rows = received_rows + v_rows,
      status = case when received_chunks + 1 >= expected_chunks then 'ready'::public.etl_batch_status
                    else 'receiving'::public.etl_batch_status end,
      last_activity_at = now()
  where id = p_batch_id
  returning * into v_batch;

  return jsonb_build_object(
    'batch_id', p_batch_id, 'chunk_index', p_chunk_index, 'duplicate', false,
    'received_chunks', v_batch.received_chunks, 'received_rows', v_batch.received_rows,
    'status', v_batch.status
  );
end;
$$;

-- Atomisk finalisering: hela batchen publiceras eller ingenting
create or replace function public.etl_finalize_batch(p_batch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_batch public.etl_batches%rowtype;
  v_chunks integer;
  v_rows integer;
  v_inserted integer := 0;
begin
  select * into v_batch from public.etl_batches where id = p_batch_id for update;
  if not found then
    raise exception 'Batch % finns inte', p_batch_id using errcode = 'no_data_found';
  end if;

  if v_batch.status = 'succeeded' then
    return jsonb_build_object('batch_id', p_batch_id, 'indicator_id', v_batch.indicator_id,
      'rows', v_batch.received_rows, 'already_finalized', true);
  end if;

  if v_batch.status = 'failed' then
    raise exception 'Batch % är avbruten', p_batch_id using errcode = 'invalid_parameter_value';
  end if;

  select count(*), coalesce(sum(row_count), 0) into v_chunks, v_rows
  from public.etl_batch_chunks where batch_id = p_batch_id;

  if v_chunks <> v_batch.expected_chunks then
    raise exception 'Alla chunkar saknas: % av % mottagna', v_chunks, v_batch.expected_chunks
      using errcode = 'invalid_parameter_value';
  end if;

  if v_batch.expected_rows is not null and v_rows <> v_batch.expected_rows then
    raise exception 'Radantal stämmer inte: % mottagna, % förväntade', v_rows, v_batch.expected_rows
      using errcode = 'invalid_parameter_value';
  end if;

  -- Advisory lock per indikator: samma skydd som publish_indicator
  perform pg_advisory_xact_lock(hashtext(v_batch.indicator_id));

  delete from public.observations where indicator_id = v_batch.indicator_id;

  insert into public.observations (indicator_id, geo_code, period, value, dimensions)
  select
    v_batch.indicator_id,
    o->>'geo_code',
    o->>'period',
    (o->>'value')::double precision,
    coalesce(o->'dimensions', '{}'::jsonb)
  from public.etl_batch_chunks c
  cross join lateral jsonb_array_elements(c.observations) o
  where c.batch_id = p_batch_id;
  get diagnostics v_inserted = row_count;

  insert into public.indicator_metadata (indicator_id, kalla, styrande_kalla, kalla_uppdaterad_datum, hamtad_datum, updated_at)
  select i.id, i.styrande_kalla, i.styrande_kalla, v_batch.kalla_uppdaterad_datum, current_date, now()
  from public.indicators i where i.id = v_batch.indicator_id
  on conflict (indicator_id) do update set
    kalla_uppdaterad_datum = coalesce(excluded.kalla_uppdaterad_datum, public.indicator_metadata.kalla_uppdaterad_datum),
    hamtad_datum = current_date,
    updated_at = now();

  if v_batch.run_id is not null then
    update public.data_source_runs
    set status = 'succeeded', finished_at = now(), rows_affected = v_inserted, error_message = null
    where id = v_batch.run_id;
  else
    insert into public.data_source_runs (source, indicator_id, status, finished_at, rows_affected)
    values (v_batch.source, v_batch.indicator_id, 'succeeded', now(), v_inserted);
  end if;

  update public.etl_batches
  set status = 'succeeded', received_rows = v_rows, error_message = null, last_activity_at = now()
  where id = p_batch_id;

  -- Frigör stagingutrymme när publiceringen lyckats (samma transaktion)
  delete from public.etl_batch_chunks where batch_id = p_batch_id;

  return jsonb_build_object('batch_id', p_batch_id, 'indicator_id', v_batch.indicator_id,
    'rows', v_inserted, 'already_finalized', false);
end;
$$;

-- Avbryt batch
create or replace function public.etl_abort_batch(p_batch_id uuid, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_batch public.etl_batches%rowtype;
begin
  select * into v_batch from public.etl_batches where id = p_batch_id for update;
  if not found then
    raise exception 'Batch % finns inte', p_batch_id using errcode = 'no_data_found';
  end if;

  if v_batch.status = 'succeeded' then
    raise exception 'Batch % är redan publicerad', p_batch_id using errcode = 'invalid_parameter_value';
  end if;

  delete from public.etl_batch_chunks where batch_id = p_batch_id;

  update public.etl_batches
  set status = 'failed', error_message = coalesce(p_reason, 'Avbruten av ETL-jobbet'), last_activity_at = now()
  where id = p_batch_id;

  if v_batch.run_id is not null then
    update public.data_source_runs
    set status = 'failed', finished_at = now(), error_message = coalesce(p_reason, 'Batch avbruten')
    where id = v_batch.run_id;
  end if;

  return jsonb_build_object('batch_id', p_batch_id, 'status', 'failed');
end;
$$;

-- Städning av övergivna/avslutade batcher (inget schemalagt jobb ännu)
create or replace function public.etl_cleanup_batches(p_older_than interval default interval '48 hours')
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
begin
  with removed as (
    delete from public.etl_batches
    where last_activity_at < now() - p_older_than
    returning 1
  )
  select count(*) into v_count from removed;
  return v_count;
end;
$$;

revoke execute on function public.etl_start_batch(text, text, integer, integer, date, uuid) from public, anon, authenticated;
revoke execute on function public.etl_store_chunk(uuid, text, integer, jsonb, text) from public, anon, authenticated;
revoke execute on function public.etl_finalize_batch(uuid) from public, anon, authenticated;
revoke execute on function public.etl_abort_batch(uuid, text) from public, anon, authenticated;
revoke execute on function public.etl_cleanup_batches(interval) from public, anon, authenticated;

grant execute on function public.etl_start_batch(text, text, integer, integer, date, uuid) to service_role;
grant execute on function public.etl_store_chunk(uuid, text, integer, jsonb, text) to service_role;
grant execute on function public.etl_finalize_batch(uuid) to service_role;
grant execute on function public.etl_abort_batch(uuid, text) to service_role;
grant execute on function public.etl_cleanup_batches(interval) to service_role;
