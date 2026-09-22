alter table public.observations
  drop constraint if exists observations_batch_indicator_geo_period_dimensions_key;

create index if not exists observations_batch_id_idx
  on public.observations (batch_id);

create or replace function public.etl_cleanup_failed_batch(
  p_batch_id uuid,
  p_max_rows integer default 50000
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_batch public.etl_batches%rowtype;
  v_deleted integer;
  v_remaining boolean;
begin
  if p_max_rows < 1 or p_max_rows > 50000 then
    raise exception 'p_max_rows måste vara mellan 1 och 50000'
      using errcode = 'invalid_parameter_value';
  end if;

  select * into v_batch
  from public.etl_batches
  where id = p_batch_id
  for update;

  if not found then
    raise exception 'Batch % finns inte', p_batch_id
      using errcode = 'no_data_found';
  end if;

  if v_batch.status <> 'failed' then
    raise exception 'Endast misslyckade batchar kan städas (status: %)', v_batch.status
      using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    select 1
    from public.indicator_active_batches
    where active_batch_id = p_batch_id
  ) then
    raise exception 'En aktiv batch får aldrig städas'
      using errcode = 'invalid_parameter_value';
  end if;

  with deleted_rows as (
    delete from public.observations as target
    where target.ctid in (
      select candidate.ctid
      from public.observations as candidate
      where candidate.batch_id = p_batch_id
      limit p_max_rows
    )
    returning 1
  )
  select count(*) into v_deleted
  from deleted_rows;

  select exists (
    select 1
    from public.observations
    where batch_id = p_batch_id
  ) into v_remaining;

  if not v_remaining then
    delete from public.etl_batch_chunks
    where batch_id = p_batch_id;
  end if;

  update public.etl_batches
  set last_activity_at = now()
  where id = p_batch_id;

  return jsonb_build_object(
    'batch_id', p_batch_id,
    'deleted_rows', v_deleted,
    'remaining', v_remaining
  );
end;
$$;

revoke execute on function public.etl_cleanup_failed_batch(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.etl_cleanup_failed_batch(uuid, integer)
  to service_role;