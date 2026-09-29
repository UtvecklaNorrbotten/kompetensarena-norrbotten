-- Inkrementell, atomisk ETL för månadsdata.
-- Historiken ligger kvar i indikatorns aktiva batch. En ny månadsperiod tas först
-- emot i en liten osynlig stagingbatch. Vid finalisering ersätts endast den
-- angivna perioden i den aktiva batchen, i en enda databastransaktion.
-- Därmed behöver miljoner historiska rader varken laddas om eller kopieras varje månad.

alter table public.etl_batches
  add column if not exists base_batch_id uuid references public.etl_batches(id) on delete set null,
  add column if not exists replace_period text;

create or replace function public.etl_start_period_batch(
  p_indicator_id text,
  p_source text,
  p_replace_period text,
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
declare
  v_id uuid;
  v_base_batch_id uuid;
begin
  if p_replace_period is null or length(trim(p_replace_period)) = 0 then
    raise exception 'replace_period måste anges' using errcode = 'invalid_parameter_value';
  end if;

  if p_expected_chunks < 1 or p_expected_chunks > 2000 then
    raise exception 'expected_chunks utanför tillåtet intervall' using errcode = 'invalid_parameter_value';
  end if;

  if p_expected_rows < 0 then
    raise exception 'expected_rows får inte vara negativt' using errcode = 'invalid_parameter_value';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_indicator_id));

  select active_batch_id
  into v_base_batch_id
  from public.indicator_active_batches
  where indicator_id = p_indicator_id;

  if v_base_batch_id is null then
    raise exception 'Indikator % saknar aktiv historisk batch; kör full backfill först', p_indicator_id
      using errcode = 'no_data_found';
  end if;

  insert into public.etl_batches (
    indicator_id,
    source,
    kalla_uppdaterad_datum,
    expected_chunks,
    expected_rows,
    received_chunks,
    received_rows,
    status,
    run_id,
    base_batch_id,
    replace_period
  )
  values (
    p_indicator_id,
    p_source,
    p_kalla_uppdaterad_datum,
    p_expected_chunks,
    p_expected_rows,
    0,
    0,
    'started',
    p_run_id,
    v_base_batch_id,
    p_replace_period
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- Fulla batchar fortsätter byta aktiv batch som tidigare.
-- Periodbatchar flyttar däremot bara den nya periodens staged rader in i den
-- redan aktiva historikbatchen efter att den gamla versionen av perioden tagits bort.
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
  v_current_active uuid;
begin
  select * into v_batch
  from public.etl_batches
  where id = p_batch_id
  for update;

  if not found then
    raise exception 'Batch % finns inte', p_batch_id using errcode = 'no_data_found';
  end if;

  if v_batch.status = 'succeeded' then
    return jsonb_build_object(
      'batch_id', p_batch_id,
      'indicator_id', v_batch.indicator_id,
      'rows', v_batch.received_rows,
      'replace_period', v_batch.replace_period,
      'already_finalized', true
    );
  end if;

  if v_batch.status = 'failed' then
    raise exception 'Batch % är avbruten', p_batch_id using errcode = 'invalid_parameter_value';
  end if;

  select count(*)
  into v_chunks
  from public.etl_batch_chunks
  where batch_id = p_batch_id;

  if v_chunks <> v_batch.expected_chunks then
    raise exception 'Alla chunkar saknas: % av % mottagna', v_chunks, v_batch.expected_chunks
      using errcode = 'invalid_parameter_value';
  end if;

  select count(*)
  into v_rows
  from public.observations
  where batch_id = p_batch_id
    and indicator_id = v_batch.indicator_id;

  if v_batch.expected_rows is not null and v_rows <> v_batch.expected_rows then
    raise exception 'Radantal stämmer inte: % staged, % förväntade', v_rows, v_batch.expected_rows
      using errcode = 'invalid_parameter_value';
  end if;

  perform pg_advisory_xact_lock(hashtext(v_batch.indicator_id));

  if v_batch.replace_period is not null then
    select active_batch_id
    into v_current_active
    from public.indicator_active_batches
    where indicator_id = v_batch.indicator_id
    for update;

    if v_current_active is distinct from v_batch.base_batch_id then
      raise exception 'Aktiv batch ändrades under periodimporten'
        using errcode = 'serialization_failure';
    end if;

    if exists (
      select 1
      from public.observations
      where batch_id = p_batch_id
        and period <> v_batch.replace_period
    ) then
      raise exception 'Periodbatchen innehåller rader utanför %', v_batch.replace_period
        using errcode = 'invalid_parameter_value';
    end if;

    delete from public.observations
    where batch_id = v_batch.base_batch_id
      and indicator_id = v_batch.indicator_id
      and period = v_batch.replace_period;

    update public.observations
    set batch_id = v_batch.base_batch_id
    where batch_id = p_batch_id
      and indicator_id = v_batch.indicator_id;
  else
    insert into public.indicator_active_batches (
      indicator_id, active_batch_id, activated_at
    )
    values (
      v_batch.indicator_id, p_batch_id, now()
    )
    on conflict (indicator_id) do update set
      active_batch_id = excluded.active_batch_id,
      activated_at = excluded.activated_at;
  end if;

  insert into public.indicator_metadata (
    indicator_id,
    kalla,
    styrande_kalla,
    kalla_uppdaterad_datum,
    hamtad_datum,
    period,
    updated_at
  )
  select
    i.id,
    v_batch.source,
    i.styrande_kalla,
    v_batch.kalla_uppdaterad_datum,
    current_date,
    v_batch.replace_period,
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
    period = coalesce(excluded.period, public.indicator_metadata.period),
    updated_at = now();

  if v_batch.run_id is not null then
    update public.data_source_runs
    set status = 'succeeded',
        finished_at = now(),
        rows_affected = v_rows,
        error_message = null
    where id = v_batch.run_id;
  else
    insert into public.data_source_runs (
      source, indicator_id, status, finished_at, rows_affected
    )
    values (
      v_batch.source, v_batch.indicator_id, 'succeeded', now(), v_rows
    );
  end if;

  update public.etl_batches
  set status = 'succeeded',
      received_rows = v_rows,
      error_message = null,
      last_activity_at = now()
  where id = p_batch_id;

  delete from public.etl_batch_chunks
  where batch_id = p_batch_id;

  return jsonb_build_object(
    'batch_id', p_batch_id,
    'indicator_id', v_batch.indicator_id,
    'rows', v_rows,
    'base_batch_id', v_batch.base_batch_id,
    'replace_period', v_batch.replace_period,
    'already_finalized', false
  );
end;
$$;

revoke execute on function public.etl_start_period_batch(
  text, text, text, integer, integer, date, uuid
) from public, anon, authenticated;
grant execute on function public.etl_start_period_batch(
  text, text, text, integer, integer, date, uuid
) to service_role;

revoke execute on function public.etl_finalize_batch(uuid)
  from public, anon, authenticated;
grant execute on function public.etl_finalize_batch(uuid)
  to service_role;

notify pgrst, 'reload schema';
