-- Gör finalisering av fulla historikbatchar O(antal chunkar) i stället för
-- O(antal observationer). Periodbatchar är små och verifieras fortsatt mot staged rader.
-- Detta undviker timeout när en full AF-backfill innehåller miljontals observationer.

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

  select count(*), coalesce(sum(row_count), 0)
  into v_chunks, v_rows
  from public.etl_batch_chunks
  where batch_id = p_batch_id;

  if v_chunks <> v_batch.expected_chunks then
    raise exception 'Alla chunkar saknas: % av % mottagna', v_chunks, v_batch.expected_chunks
      using errcode = 'invalid_parameter_value';
  end if;

  -- För periodbatchar räknas staged observationer eftersom de senare flyttas
  -- till den aktiva historikbatchen. För fulla batchar motsvarar summan av
  -- etl_batch_chunks exakt de mottagna observationerna och är mycket billigare
  -- än count(*) över miljontals rader i observations.
  if v_batch.replace_period is not null then
    select count(*)
    into v_rows
    from public.observations
    where batch_id = p_batch_id
      and indicator_id = v_batch.indicator_id;
  end if;

  if v_batch.expected_rows is not null and v_rows <> v_batch.expected_rows then
    raise exception 'Radantal stämmer inte: % mottagna, % förväntade', v_rows, v_batch.expected_rows
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

revoke execute on function public.etl_finalize_batch(uuid)
  from public, anon, authenticated;
grant execute on function public.etl_finalize_batch(uuid)
  to service_role;

notify pgrst, 'reload schema';