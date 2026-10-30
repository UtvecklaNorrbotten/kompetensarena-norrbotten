-- lovable-cron-fallback-reviewed: temporary drain job, needs no-timeout context for multi-million-row deletes and unschedules itself once nothing obsolete remains
create or replace function public.etl_obsolete_batch_ids()
returns table (batch_id uuid, reason text)
language sql
stable
security definer
set search_path = public
as $$
  select b.id, 'failed'
  from public.etl_batches b
  where b.status = 'failed'
    and not exists (select 1 from public.indicator_active_batches a where a.active_batch_id = b.id)
    and not exists (select 1 from public.etl_batches c where c.base_batch_id = b.id)
  union all
  select b.id, 'superseded'
  from public.etl_batches b
  join public.indicator_active_batches a on a.indicator_id = b.indicator_id
  join public.etl_batches act on act.id = a.active_batch_id
  where b.status = 'succeeded'
    and b.id <> a.active_batch_id
    and b.replace_period is null
    and act.replace_period is null
    and act.status = 'succeeded'
    and b.created_at < act.created_at
    and not exists (select 1 from public.etl_batches c where c.base_batch_id = b.id)
$$;

create or replace function public.etl_purge_obsolete_batches(p_max_rows integer default 200000)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_left integer := p_max_rows;
  v_n integer;
  v_deleted integer := 0;
  v_removed_batches integer := 0;
begin
  if p_max_rows < 1 or p_max_rows > 500000 then
    raise exception 'p_max_rows måste vara mellan 1 och 500000' using errcode = 'invalid_parameter_value';
  end if;
  if not pg_try_advisory_xact_lock(hashtext('etl_purge_obsolete_batches')) then
    return jsonb_build_object('skipped', 'already_running');
  end if;

  for r in select * from public.etl_obsolete_batch_ids() loop
    perform pg_advisory_xact_lock(hashtext((select indicator_id from public.etl_batches where id = r.batch_id)));
    if not exists (select 1 from public.etl_obsolete_batch_ids() o where o.batch_id = r.batch_id) then
      continue;
    end if;

    if v_left > 0 then
      delete from public.observations o
      where o.id in (select id from public.observations where batch_id = r.batch_id limit v_left);
      get diagnostics v_n = row_count;
      v_deleted := v_deleted + v_n;
      v_left := v_left - v_n;
    end if;

    if not exists (select 1 from public.observations where batch_id = r.batch_id) then
      delete from public.etl_batch_chunks where batch_id = r.batch_id;
      delete from public.etl_batches where id = r.batch_id;
      v_removed_batches := v_removed_batches + 1;
    end if;

    exit when v_left <= 0;
  end loop;

  if not exists (select 1 from public.etl_obsolete_batch_ids()) then
    begin
      perform cron.unschedule('etl-purge-obsolete-batches');
    exception when others then null;
    end;
  end if;

  return jsonb_build_object('deleted_rows', v_deleted, 'removed_batches', v_removed_batches);
end;
$$;

revoke execute on function public.etl_obsolete_batch_ids() from public, anon, authenticated;
revoke execute on function public.etl_purge_obsolete_batches(integer) from public, anon, authenticated;
grant execute on function public.etl_obsolete_batch_ids() to service_role;
grant execute on function public.etl_purge_obsolete_batches(integer) to service_role;

select cron.schedule('etl-purge-obsolete-batches', '* * * * *', 'select public.etl_purge_obsolete_batches(200000)');