-- Versionsstyrd ETL-publicering för stora dataset.
--
-- Observationer skrivs löpande till en ny batch-version. Frontend får bara
-- läsa den batch som pekas ut som aktiv för indikatorn. Finalisering blir
-- därför ett kort, atomiskt byte av en referens i stället för en massinsert.

-- En observation kan höra till en importerad batch. Äldre/små importer kan
-- fortsatt vara batchlösa tills de successivt flyttas till samma mönster.
alter table public.observations
  add column if not exists batch_id uuid references public.etl_batches(id) on delete cascade;

alter table public.observations
  drop constraint if exists observations_indicator_id_geo_code_period_dimensions_key;

alter table public.observations
  add constraint observations_batch_indicator_geo_period_dimensions_key
  unique (batch_id, indicator_id, geo_code, period, dimensions);

create index if not exists observations_indicator_batch_idx
  on public.observations (indicator_id, batch_id);

-- En rad per indikator avgör vilken importerad batch som är synlig.
create table if not exists public.indicator_active_batches (
  indicator_id text primary key references public.indicators(id) on delete cascade,
  active_batch_id uuid not null references public.etl_batches(id) on delete restrict,
  activated_at timestamptz not null default now()
);

grant select on public.indicator_active_batches to anon;
grant select on public.indicator_active_batches to authenticated;
grant all on public.indicator_active_batches to service_role;
alter table public.indicator_active_batches enable row level security;

drop policy if exists "Aktiva batchar är publika" on public.indicator_active_batches;
create policy "Aktiva batchar är publika" on public.indicator_active_batches
  for select to anon, authenticated using (true);

-- Bara den aktiva batchen får läsas publikt. Indikatorer som ännu använder
-- äldre batchlös publicering fungerar oförändrat tills de får sin första batch.
drop policy if exists "Publika observationer läsbara av alla" on public.observations;
drop policy if exists "Inloggade ser observationer enligt nivå" on public.observations;

create policy "Publika aktiva observationer läsbara av alla" on public.observations
  for select to anon
  using (
    exists (
      select 1
      from public.indicators i
      where i.id = observations.indicator_id
        and i.visibility = 'publik'
    )
    and (
      exists (
        select 1
        from public.indicator_active_batches a
        where a.indicator_id = observations.indicator_id
          and a.active_batch_id = observations.batch_id
      )
      or (
        observations.batch_id is null
        and not exists (
          select 1
          from public.indicator_active_batches a
          where a.indicator_id = observations.indicator_id
        )
      )
    )
  );

create policy "Inloggade ser aktiva observationer enligt nivå" on public.observations
  for select to authenticated
  using (
    exists (
      select 1
      from public.indicators i
      where i.id = observations.indicator_id
        and (
          i.visibility in ('publik', 'inloggad')
          or public.has_role(auth.uid(), 'admin')
        )
    )
    and (
      exists (
        select 1
        from public.indicator_active_batches a
        where a.indicator_id = observations.indicator_id
          and a.active_batch_id = observations.batch_id
      )
      or (
        observations.batch_id is null
        and not exists (
          select 1
          from public.indicator_active_batches a
          where a.indicator_id = observations.indicator_id
        )
      )
    )
  );

-- Äldre, oavslutade JSONB-batchar kan inte slutföras efter modellbytet.
-- De markeras därför explicit som misslyckade innan deras råa stagingdata tas bort.
update public.etl_batches
set status = 'failed',
    error_message = coalesce(error_message, 'Avbruten vid byte till versionsstyrd ETL-publicering'),
    last_activity_at = now()
where status in ('started', 'receiving', 'ready');

update public.data_source_runs r
set status = 'failed',
    finished_at = coalesce(r.finished_at, now()),
    error_message = coalesce(r.error_message, 'Avbruten vid byte till versionsstyrd ETL-publicering')
from public.etl_batches b
where b.run_id = r.id
  and b.status = 'failed'
  and r.status = 'started';

-- Chunks behåller endast integritetsuppgifter. Råobservationerna lagras
-- normaliserat direkt i observations-tabellen under den osynliga batchen.
alter table public.etl_batch_chunks
  drop column if exists observations;

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

  insert into public.observations (batch_id, indicator_id, geo_code, period, value, dimensions)
  select
    p_batch_id,
    v_batch.indicator_id,
    o->>'geo_code',
    o->>'period',
    (o->>'value')::double precision,
    coalesce(o->'dimensions', '{}'::jsonb)
  from jsonb_array_elements(p_observations) o;

  insert into public.etl_batch_chunks (batch_id, chunk_index, row_count, checksum)
  values (p_batch_id, p_chunk_index, v_rows, p_checksum);

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

-- Finalisering gör bara en atomisk växling av aktiv batch. Alla stora inserts
-- har redan gjorts i de enskilda chunk-anropen.
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
begin
  select * into v_batch from public.etl_batches where id = p_batch_id for update;
  if not found then
    raise exception 'Batch % finns inte', p_batch_id using errcode = 'no_data_found';
  end if;

  if v_batch.status = 'succeeded' then
    return jsonb_build_object(
      'batch_id', p_batch_id,
      'indicator_id', v_batch.indicator_id,
      'rows', v_batch.received_rows,
      'already_finalized', true
    );
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

  perform pg_advisory_xact_lock(hashtext(v_batch.indicator_id));

  insert into public.indicator_active_batches (indicator_id, active_batch_id, activated_at)
  values (v_batch.indicator_id, p_batch_id, now())
  on conflict (indicator_id) do update set
    active_batch_id = excluded.active_batch_id,
    activated_at = excluded.activated_at;

  insert into public.indicator_metadata (
    indicator_id, kalla, styrande_kalla, kalla_uppdaterad_datum, hamtad_datum, updated_at
  )
  select
    i.id,
    v_batch.source,
    i.styrande_kalla,
    v_batch.kalla_uppdaterad_datum,
    current_date,
    now()
  from public.indicators i
  where i.id = v_batch.indicator_id
  on conflict (indicator_id) do update set
    kalla = excluded.kalla,
    kalla_uppdaterad_datum = coalesce(
      excluded.kalla_uppdaterad_datum,
      public.indicator_metadata.kalla_uppdaterad_datum
    ),
    hamtad_datum = current_date,
    updated_at = now();

  if v_batch.run_id is not null then
    update public.data_source_runs
    set status = 'succeeded',
        finished_at = now(),
        rows_affected = v_rows,
        error_message = null
    where id = v_batch.run_id;
  else
    insert into public.data_source_runs (source, indicator_id, status, finished_at, rows_affected)
    values (v_batch.source, v_batch.indicator_id, 'succeeded', now(), v_rows);
  end if;

  update public.etl_batches
  set status = 'succeeded',
      received_rows = v_rows,
      error_message = null,
      last_activity_at = now()
  where id = p_batch_id;

  delete from public.etl_batch_chunks where batch_id = p_batch_id;

  return jsonb_build_object(
    'batch_id', p_batch_id,
    'indicator_id', v_batch.indicator_id,
    'rows', v_rows,
    'already_finalized', false
  );
end;
$$;

-- Ett misslyckat importförsök görs omedelbart osynligt. Raderna kan städas
-- separat senare, så att avbrottet aldrig behöver radera miljontals rader
-- i samma request.
create or replace function public.etl_abort_batch(
  p_batch_id uuid,
  p_reason text default null
)
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

  update public.etl_batches
  set status = 'failed',
      error_message = coalesce(p_reason, 'Avbruten av ETL-jobbet'),
      last_activity_at = now()
  where id = p_batch_id;

  if v_batch.run_id is not null then
    update public.data_source_runs
    set status = 'failed',
        finished_at = now(),
        error_message = coalesce(p_reason, 'Batch avbruten')
    where id = v_batch.run_id;
  end if;

  return jsonb_build_object('batch_id', p_batch_id, 'status', 'failed');
end;
$$;

-- Små, manuella finaliseringstester använder en separat, osynlig indikator.
insert into public.indicators (
  id, name, description, unit, styrande_kalla, source_table_id, frequency, visibility, is_example
)
values (
  'e3-matchning-utbildning-etl-test',
  'E3 matchning utbildning – ETL-test',
  'Teknisk kontrollindikator för E3-import. Visas inte publikt.',
  'procent',
  'TAB6929',
  'TAB6929',
  'årlig',
  'admin',
  false
)
on conflict (id) do nothing;

revoke execute on function public.etl_store_chunk(uuid, text, integer, jsonb, text)
  from public, anon, authenticated;
revoke execute on function public.etl_finalize_batch(uuid)
  from public, anon, authenticated;
revoke execute on function public.etl_abort_batch(uuid, text)
  from public, anon, authenticated;

grant execute on function public.etl_store_chunk(uuid, text, integer, jsonb, text) to service_role;
grant execute on function public.etl_finalize_batch(uuid) to service_role;
grant execute on function public.etl_abort_batch(uuid, text) to service_role;
