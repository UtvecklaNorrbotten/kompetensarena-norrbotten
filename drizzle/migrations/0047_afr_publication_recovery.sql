-- Serialize BEFORE locking afr_syncs. A gateway timeout can leave the original
-- transaction running, so a retry must return busy instead of waiting on itself.
alter function public.afr_finalize_sync(uuid, jsonb) rename to afr_finalize_sync_apply;
revoke all on function public.afr_finalize_sync_apply(uuid, jsonb) from public, anon, authenticated, service_role;

create function public.afr_finalize_sync(p_sync_id uuid, p_stats jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = public
set statement_timeout = '600s' set lock_timeout = '5s' as $$
declare v_result jsonb; v_run uuid; v_state text; v_message text; v_context text; v_started timestamptz := clock_timestamp();
begin
  if not pg_try_advisory_xact_lock(hashtext('scb-afr')) then
    return jsonb_build_object('status', 'busy', 'sync_id', p_sync_id,
      'activity', coalesce((select jsonb_agg(jsonb_build_object(
        'pid', a.pid, 'query_start', a.query_start, 'wait_event_type', a.wait_event_type,
        'wait_event', a.wait_event, 'blocking_pids', pg_blocking_pids(a.pid)))
        from pg_stat_activity a where a.pid <> pg_backend_pid() and a.datname = current_database()
          and a.state = 'active' and a.query like '%afr_finalize_sync%'), '[]'::jsonb));
  end if;
  begin
    v_result := afr_finalize_sync_apply(p_sync_id, p_stats);
    return v_result || jsonb_build_object('status', 'succeeded');
  exception when query_canceled or others then
    get stacked diagnostics v_state = returned_sqlstate, v_message = message_text, v_context = pg_exception_context;
    -- The inner transaction has rolled back all publication writes. Keep staging
    -- and record the SQL location and elapsed time for a later retry/diagnosis.
    update afr_syncs set error_message = v_message, last_activity_at = now(),
      stats = coalesce(stats, '{}'::jsonb) || jsonb_build_object('last_publication_error', jsonb_build_object(
        'code', v_state, 'message', v_message, 'context', v_context,
        'at', clock_timestamp(), 'duration_seconds', extract(epoch from clock_timestamp() - v_started)))
      where id = p_sync_id and status = 'receiving' returning run_id into v_run;
    if found then
      update data_source_runs set status = 'failed', finished_at = now(), error_message = v_message where id = v_run;
      update data_source_state set last_status = 'failed', last_error = v_message,
        last_checked_at = now(), updated_at = now() where source_id = 'scb-afr';
    end if;
    return jsonb_build_object('status', case when v_state in ('55P03','57014','40P01','40001') then 'retryable' else 'blocked' end,
      'sync_id', p_sync_id, 'code', v_state, 'message', v_message);
  end;
end $$;
revoke all on function public.afr_finalize_sync(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.afr_finalize_sync(uuid, jsonb) to service_role;

-- Abort must use the same lock order, and cannot clear a committed publication.
alter function public.afr_abort_sync(uuid, text) rename to afr_abort_sync_apply;
revoke all on function public.afr_abort_sync_apply(uuid, text) from public, anon, authenticated, service_role;
create function public.afr_abort_sync(p_sync_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public set lock_timeout = '5s' as $$
begin
  if not pg_try_advisory_xact_lock(hashtext('scb-afr')) then
    raise exception 'AFR-publicering pågår; försök igen efter statuskontroll' using errcode = 'lock_not_available';
  end if;
  return afr_abort_sync_apply(p_sync_id, p_reason);
end $$;
revoke all on function public.afr_abort_sync(uuid, text) from public, anon, authenticated;
grant execute on function public.afr_abort_sync(uuid, text) to service_role;
