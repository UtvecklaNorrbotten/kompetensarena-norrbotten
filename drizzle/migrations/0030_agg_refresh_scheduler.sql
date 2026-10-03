create extension if not exists pg_cron;

-- Uppdaterar alla inaktuella aggregat.
-- Inaktuellt = källans markör (aktiv batch / AFR-källdatum) skiljer sig från senast beräknade.
create or replace function public.agg_refresh_due()
returns jsonb language plpgsql security definer set search_path = public set statement_timeout = '1800s' as $$
declare r record; v_marker text; v_afr text; v_done jsonb := '[]'::jsonb;
begin
  if not exists (select 1 from afr_syncs where status in ('started', 'receiving', 'ready')) then
    select source_date into v_afr from afr_syncs where status = 'succeeded' order by finalized_at desc nulls last limit 1;
    if v_afr is not null and v_afr is distinct from (select source_marker from agg_refresh_state where name = 'afr') then
      perform agg_refresh_afr(); v_done := v_done || '"afr"'::jsonb;
    end if;
  end if;

  select active_batch_id::text into v_marker from indicator_active_batches where indicator_id = 'e3-matchning-utbildning';
  if v_marker is not null and v_marker is distinct from (select source_marker from agg_refresh_state where name = 'e3') then
    perform agg_refresh_e3(); v_done := v_done || '"e3"'::jsonb;
  end if;

  for r in select indicator_id, active_batch_id::text b from indicator_active_batches where indicator_id like 'af-%' order by indicator_id loop
    if r.b is distinct from (select source_marker from agg_refresh_state where name = 'af:' || r.indicator_id) then
      perform agg_refresh_af(r.indicator_id); v_done := v_done || to_jsonb(r.indicator_id);
    end if;
  end loop;
  return jsonb_build_object('refreshed', v_done);
end $$;

revoke all on function public.agg_refresh_due() from public, anon, authenticated;
grant execute on function public.agg_refresh_due() to service_role;

select cron.schedule('agg-refresh-due', '17 * * * *', $$select public.agg_refresh_due()$$);