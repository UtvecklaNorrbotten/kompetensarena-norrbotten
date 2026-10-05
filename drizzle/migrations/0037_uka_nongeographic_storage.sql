-- UKÄ: icke-geografisk, versionsstyrd observationslagring.
-- Lärosäte är en egen dimension; geo_code används inte.

create table public.uka_batches (
  id uuid primary key default gen_random_uuid(),
  indicator_id text not null references public.indicators(id) on delete cascade,
  source text not null default 'UKÄ',
  kalla_uppdaterad_datum date,
  expected_chunks integer not null check (expected_chunks > 0 and expected_chunks <= 10000),
  received_chunks integer not null default 0,
  expected_rows integer not null check (expected_rows >= 0),
  received_rows integer not null default 0,
  status text not null default 'receiving'
    check (status in ('receiving','ready','succeeded','failed')),
  run_id uuid references public.data_source_runs(id) on delete set null,
  created_at timestamptz not null default now(),
  last_activity_at timestamptz not null default now(),
  finalized_at timestamptz
);

create table public.uka_batch_chunks (
  batch_id uuid not null references public.uka_batches(id) on delete cascade,
  chunk_index integer not null check (chunk_index >= 0),
  row_count integer not null check (row_count >= 0),
  checksum text not null,
  created_at timestamptz not null default now(),
  primary key (batch_id, chunk_index)
);

create table public.uka_observations (
  id bigint generated always as identity primary key,
  batch_id uuid not null references public.uka_batches(id) on delete cascade,
  indicator_id text not null references public.indicators(id) on delete cascade,
  period text not null,
  university text not null,
  gender text,
  value double precision,
  dimensions jsonb not null default '{}'::jsonb
);

create unique index uka_observations_unique_idx
  on public.uka_observations (
    batch_id,
    indicator_id,
    period,
    university,
    coalesce(gender, ''),
    dimensions
  );

create index uka_observations_indicator_batch_idx
  on public.uka_observations (indicator_id, batch_id);
create index uka_observations_university_idx
  on public.uka_observations (university);
create index uka_observations_period_idx
  on public.uka_observations (period);

create table public.uka_active_batches (
  indicator_id text primary key references public.indicators(id) on delete cascade,
  active_batch_id uuid not null references public.uka_batches(id) on delete restrict,
  activated_at timestamptz not null default now()
);

grant all on public.uka_batches, public.uka_batch_chunks, public.uka_observations, public.uka_active_batches to service_role;
grant select on public.uka_observations, public.uka_active_batches to anon, authenticated;

alter table public.uka_batches enable row level security;
alter table public.uka_batch_chunks enable row level security;
alter table public.uka_observations enable row level security;
alter table public.uka_active_batches enable row level security;

create policy "UKÄ aktiva batchar är publika"
  on public.uka_active_batches for select to anon, authenticated using (true);

create policy "Publika UKÄ-observationer"
  on public.uka_observations for select to anon
  using (
    exists (
      select 1 from public.indicators i
      where i.id = uka_observations.indicator_id
        and i.visibility = 'publik'
    )
    and exists (
      select 1 from public.uka_active_batches a
      where a.indicator_id = uka_observations.indicator_id
        and a.active_batch_id = uka_observations.batch_id
    )
  );

create policy "Inloggade UKÄ-observationer"
  on public.uka_observations for select to authenticated
  using (
    exists (
      select 1 from public.indicators i
      where i.id = uka_observations.indicator_id
        and (
          i.visibility in ('publik','inloggad')
          or public.has_role(auth.uid(), 'admin')
        )
    )
    and exists (
      select 1 from public.uka_active_batches a
      where a.indicator_id = uka_observations.indicator_id
        and a.active_batch_id = uka_observations.batch_id
    )
  );

create or replace function public.uka_start_batch(
  p_indicator_id text,
  p_source text,
  p_expected_chunks integer,
  p_expected_rows integer,
  p_kalla_uppdaterad_datum date default null,
  p_run_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  if not exists (
    select 1 from public.indicators
    where id = p_indicator_id and id like 'uka-%'
  ) then
    raise exception 'Okänd UKÄ-indikator %', p_indicator_id using errcode = 'no_data_found';
  end if;

  insert into public.uka_batches (
    indicator_id, source, expected_chunks, expected_rows,
    kalla_uppdaterad_datum, run_id
  )
  values (
    p_indicator_id, p_source, p_expected_chunks, p_expected_rows,
    p_kalla_uppdaterad_datum, p_run_id
  )
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.uka_store_chunk(
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
set statement_timeout = '180s'
as $$
declare
  v_batch public.uka_batches%rowtype;
  v_existing public.uka_batch_chunks%rowtype;
  v_rows integer;
begin
  select * into v_batch
  from public.uka_batches
  where id = p_batch_id
  for update;

  if not found then
    raise exception 'UKÄ-batch % finns inte', p_batch_id using errcode = 'no_data_found';
  end if;
  if v_batch.status not in ('receiving','ready') then
    raise exception 'UKÄ-batch har status %', v_batch.status using errcode = 'invalid_parameter_value';
  end if;
  if v_batch.indicator_id is distinct from p_indicator_id then
    raise exception 'Fel indikator för UKÄ-batch' using errcode = 'invalid_parameter_value';
  end if;
  if p_chunk_index < 0 or p_chunk_index >= v_batch.expected_chunks then
    raise exception 'UKÄ chunk_index utanför intervallet' using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_observations) o
    where not (o ? 'period' and o ? 'university')
       or coalesce(o->>'period','') = ''
       or coalesce(o->>'university','') = ''
       or o ? 'geo_code'
  ) then
    raise exception 'Ogiltig UKÄ-observation' using errcode = 'invalid_parameter_value';
  end if;

  select * into v_existing
  from public.uka_batch_chunks
  where batch_id = p_batch_id and chunk_index = p_chunk_index;

  if found then
    if v_existing.checksum = p_checksum then
      return jsonb_build_object('duplicate', true, 'chunk_index', p_chunk_index);
    end if;
    raise exception 'UKÄ-chunk finns redan med annat innehåll' using errcode = 'unique_violation';
  end if;

  v_rows := jsonb_array_length(p_observations);

  insert into public.uka_observations (
    batch_id, indicator_id, period, university, gender, value, dimensions
  )
  select
    p_batch_id,
    p_indicator_id,
    o->>'period',
    o->>'university',
    nullif(o->>'gender',''),
    (o->>'value')::double precision,
    coalesce(o->'dimensions','{}'::jsonb)
  from jsonb_array_elements(p_observations) o;

  insert into public.uka_batch_chunks (batch_id, chunk_index, row_count, checksum)
  values (p_batch_id, p_chunk_index, v_rows, p_checksum);

  update public.uka_batches
  set received_chunks = received_chunks + 1,
      received_rows = received_rows + v_rows,
      status = case
        when received_chunks + 1 >= expected_chunks then 'ready'
        else 'receiving'
      end,
      last_activity_at = now()
  where id = p_batch_id;

  return jsonb_build_object('duplicate', false, 'chunk_index', p_chunk_index, 'rows', v_rows);
end;
$$;

create or replace function public.uka_finalize_batch(p_batch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_batch public.uka_batches%rowtype;
  v_old uuid;
begin
  select * into v_batch
  from public.uka_batches
  where id = p_batch_id
  for update;

  if not found then
    raise exception 'UKÄ-batch % finns inte', p_batch_id using errcode = 'no_data_found';
  end if;
  if v_batch.status = 'succeeded' then
    return jsonb_build_object('batch_id', p_batch_id, 'rows', v_batch.received_rows, 'already_finalized', true);
  end if;
  if v_batch.status <> 'ready'
     or v_batch.received_chunks <> v_batch.expected_chunks
     or v_batch.received_rows <> v_batch.expected_rows then
    raise exception 'UKÄ-batch är inte komplett' using errcode = 'invalid_parameter_value';
  end if;

  perform pg_advisory_xact_lock(hashtext(v_batch.indicator_id));

  select active_batch_id into v_old
  from public.uka_active_batches
  where indicator_id = v_batch.indicator_id;

  insert into public.uka_active_batches (indicator_id, active_batch_id, activated_at)
  values (v_batch.indicator_id, p_batch_id, now())
  on conflict (indicator_id) do update
  set active_batch_id = excluded.active_batch_id,
      activated_at = excluded.activated_at;

  insert into public.indicator_metadata (
    indicator_id, kalla, styrande_kalla,
    kalla_uppdaterad_datum, hamtad_datum, updated_at
  )
  select
    i.id, i.styrande_kalla, i.styrande_kalla,
    v_batch.kalla_uppdaterad_datum, current_date, now()
  from public.indicators i
  where i.id = v_batch.indicator_id
  on conflict (indicator_id) do update set
    kalla_uppdaterad_datum = coalesce(excluded.kalla_uppdaterad_datum, public.indicator_metadata.kalla_uppdaterad_datum),
    hamtad_datum = current_date,
    updated_at = now();

  update public.uka_batches
  set status = 'succeeded', finalized_at = now(), last_activity_at = now()
  where id = p_batch_id;

  if v_batch.run_id is not null then
    update public.data_source_runs
    set status = 'succeeded', finished_at = now(),
        rows_affected = v_batch.received_rows, error_message = null
    where id = v_batch.run_id;
  end if;

  if v_old is not null and v_old <> p_batch_id then
    delete from public.uka_batches where id = v_old;
  end if;

  return jsonb_build_object(
    'batch_id', p_batch_id,
    'indicator_id', v_batch.indicator_id,
    'rows', v_batch.received_rows,
    'already_finalized', false
  );
end;
$$;

create or replace function public.uka_abort_batch(
  p_batch_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_batch public.uka_batches%rowtype;
begin
  select * into v_batch
  from public.uka_batches
  where id = p_batch_id
  for update;

  if not found then
    raise exception 'UKÄ-batch % finns inte', p_batch_id using errcode = 'no_data_found';
  end if;
  if v_batch.status = 'succeeded' then
    raise exception 'UKÄ-batch är redan publicerad' using errcode = 'invalid_parameter_value';
  end if;

  if v_batch.run_id is not null then
    update public.data_source_runs
    set status = 'failed', finished_at = now(),
        error_message = coalesce(p_reason, 'UKÄ-batch avbruten')
    where id = v_batch.run_id;
  end if;

  delete from public.uka_batches where id = p_batch_id;

  return jsonb_build_object('batch_id', p_batch_id, 'status', 'failed');
end;
$$;

revoke execute on function public.uka_start_batch(text,text,integer,integer,date,uuid) from public, anon, authenticated;
revoke execute on function public.uka_store_chunk(uuid,text,integer,jsonb,text) from public, anon, authenticated;
revoke execute on function public.uka_finalize_batch(uuid) from public, anon, authenticated;
revoke execute on function public.uka_abort_batch(uuid,text) from public, anon, authenticated;

grant execute on function public.uka_start_batch(text,text,integer,integer,date,uuid) to service_role;
grant execute on function public.uka_store_chunk(uuid,text,integer,jsonb,text) to service_role;
grant execute on function public.uka_finalize_batch(uuid) to service_role;
grant execute on function public.uka_abort_batch(uuid,text) to service_role;
