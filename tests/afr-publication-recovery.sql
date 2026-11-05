-- Run after migration 0047, in a transaction that is ALWAYS rolled back.
begin;
do $$
declare v_result jsonb; v_id uuid; v_before jsonb;
begin
  select id, stats into v_id, v_before from afr_syncs where status = 'succeeded' order by finalized_at desc limit 1;
  if v_id is null then raise exception 'Test requires a published AFR snapshot'; end if;
  v_result := afr_finalize_sync(v_id);
  if v_result->>'status' <> 'succeeded' or not (v_result->>'already_finalized')::boolean then
    raise exception 'Committed retry not idempotent: %', v_result;
  end if;
  if (select stats from afr_syncs where id=v_id) is distinct from v_before then raise exception 'Committed stats changed'; end if;
end $$;

-- Synthetic test record only; never commits and contains no registry data.
select set_config('afr.test_sync', afr_start_sync('daily','test-publication-recovery','test',now(),0,0,0,0)::text, true);
insert into afr_stage_records(sync_id, entity, key, op)
values (current_setting('afr.test_sync')::uuid, 'je', 'synthetic-test', 'remove');

-- Simulate an operation that changes status then fails. The wrapper must roll
-- back the inner changes and retain the staging snapshot for another attempt.
create or replace function public.afr_finalize_sync_apply(p_sync_id uuid, p_stats jsonb default '{}'::jsonb)
returns jsonb language plpgsql as $$
begin
  update public.afr_syncs set status='failed' where id=p_sync_id;
  raise exception 'Synthetic lock timeout' using errcode='55P03';
end $$;
do $$
declare v_result jsonb; v_id uuid := current_setting('afr.test_sync')::uuid;
begin
  v_result := afr_finalize_sync(v_id);
  if v_result->>'status' <> 'retryable' then raise exception 'Expected retryable: %', v_result; end if;
  if not exists(select 1 from afr_stage_records where sync_id=v_id) then raise exception 'Staging lost'; end if;
  if (select status from afr_syncs where id=v_id) <> 'receiving' then raise exception 'Inner transaction not rolled back'; end if;
  if (select stats#>>'{last_publication_error,code}' from afr_syncs where id=v_id) <> '55P03' then raise exception 'Diagnostics missing'; end if;
end $$;
rollback;
