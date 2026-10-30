-- Inkrementell och idempotent UKÄ-omräkning för större åldersuppdelade importer.
-- Samma markerformat används av agg_refresh_due; publik schema/RLS ändras inte.
CREATE OR REPLACE FUNCTION public.agg_refresh_uka()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' SET statement_timeout TO '900s'
AS $function$
declare
  v_start timestamptz := clock_timestamp();
  v_rows int;
  v_marker text;
  v_previous text;
  r record;
  v_changed int := 0;
begin
  -- En väntande omräkning läser markören igen efter låset och gör inte om redan utfört arbete.
  perform pg_advisory_xact_lock(hashtext('public.agg_refresh_uka'));
  select coalesce(string_agg(indicator_id || '=' || active_batch_id::text, ',' order by indicator_id), '')
    into v_marker from uka_active_batches;
  select source_marker into v_previous from agg_refresh_state where name = 'uka';
  if v_marker is not distinct from v_previous then
    select count(*) into v_rows from agg_uka_university;
    return jsonb_build_object('rows', v_rows, 'no_change', true);
  end if;

  delete from agg_uka_university g
    where not exists (select 1 from uka_active_batches a where a.indicator_id = g.indicator_id);
  for r in select indicator_id, active_batch_id from uka_active_batches order by indicator_id loop
    if not ((r.indicator_id || '=' || r.active_batch_id::text) =
      any(coalesce(string_to_array(v_previous, ','), array[]::text[]))) then
      delete from agg_uka_university where indicator_id = r.indicator_id;
      insert into agg_uka_university (indicator_id, university, period, gender, breakdown, category, value)
      select o.indicator_id, o.university, o.period, coalesce(o.gender, 'Total'),
        coalesce((select string_agg(k, '|' order by k) from jsonb_object_keys(o.dimensions) k), ''),
        coalesce((select string_agg(o.dimensions->>k, '|' order by k) from jsonb_object_keys(o.dimensions) k), ''),
        sum(o.value)
      from uka_observations o
      where o.batch_id = r.active_batch_id and o.indicator_id = r.indicator_id
      group by 1, 2, 3, 4, 5, 6;
      v_changed := v_changed + 1;
    end if;
  end loop;
  select count(*) into v_rows from agg_uka_university;
  perform agg_mark('uka', 'lärosäte', v_rows, v_start, v_marker);
  return jsonb_build_object('rows', v_rows, 'changed_indicators', v_changed);
end $function$;
REVOKE ALL ON FUNCTION public.agg_refresh_uka() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.agg_refresh_uka() TO service_role;
