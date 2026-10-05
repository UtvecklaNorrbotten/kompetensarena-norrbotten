CREATE TABLE public.agg_uka_university (
  indicator_id text NOT NULL REFERENCES public.indicators(id),
  university text NOT NULL,
  period text NOT NULL,
  gender text NOT NULL DEFAULT 'Total',
  breakdown text NOT NULL DEFAULT '',
  category text NOT NULL DEFAULT '',
  value double precision,
  PRIMARY KEY (indicator_id, university, period, gender, breakdown, category)
);
COMMENT ON TABLE public.agg_uka_university IS 'UKÄ per lärosäte från aktiv batch. breakdown='''' = källans totalrad; annars dimensionsnycklar (sorterade, |-separerade) och category motsvarande värden.';
GRANT SELECT ON public.agg_uka_university TO anon, authenticated;
GRANT ALL ON public.agg_uka_university TO service_role;
ALTER TABLE public.agg_uka_university ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Läs UKÄ-aggregat enligt indikatorns synlighet" ON public.agg_uka_university
FOR SELECT TO anon, authenticated USING (
  EXISTS (SELECT 1 FROM public.indicators i WHERE i.id = indicator_id AND (
    i.visibility = 'publik'
    OR (auth.uid() IS NOT NULL AND i.visibility = 'inloggad')
    OR (auth.uid() IS NOT NULL AND public.has_role(auth.uid(), 'admin'))
  ))
);
CREATE INDEX agg_uka_university_total_idx ON public.agg_uka_university (indicator_id, breakdown, period, university) WHERE gender = 'Total';
CREATE INDEX agg_uka_university_uni_idx ON public.agg_uka_university (university, indicator_id, period);

CREATE OR REPLACE FUNCTION public.agg_refresh_uka()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' SET statement_timeout TO '900s'
AS $$
declare v_start timestamptz := clock_timestamp(); v_rows int; v_marker text;
begin
  select coalesce(string_agg(indicator_id || '=' || active_batch_id::text, ',' order by indicator_id), '')
    into v_marker from uka_active_batches;
  delete from agg_uka_university where true;
  insert into agg_uka_university (indicator_id, university, period, gender, breakdown, category, value)
  select o.indicator_id, o.university, o.period, coalesce(o.gender, 'Total'),
    coalesce((select string_agg(k, '|' order by k) from jsonb_object_keys(o.dimensions) k), ''),
    coalesce((select string_agg(o.dimensions->>k, '|' order by k) from jsonb_object_keys(o.dimensions) k), ''),
    sum(o.value)
  from uka_observations o join uka_active_batches a on a.active_batch_id = o.batch_id
  group by 1, 2, 3, 4, 5, 6;
  get diagnostics v_rows = row_count;
  perform agg_mark('uka', 'lärosäte', v_rows, v_start, v_marker);
  return jsonb_build_object('rows', v_rows);
end $$;
REVOKE ALL ON FUNCTION public.agg_refresh_uka() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.agg_refresh_uka() TO service_role;

CREATE OR REPLACE FUNCTION public.agg_refresh_due()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' SET statement_timeout TO '1800s'
AS $function$
declare r record; v_marker text; v_afr text; v_done jsonb := '[]'::jsonb;
begin
  if not exists (select 1 from afr_syncs where status in ('started', 'receiving', 'ready')) then
    select source_date into v_afr from afr_syncs where status = 'succeeded' order by finalized_at desc nulls last limit 1;
    if v_afr is not null and v_afr is distinct from (select source_marker from agg_refresh_state where name = 'afr') then
      perform agg_refresh_afr(); v_done := v_done || '"afr"'::jsonb;
    end if;
  end if;

  select coalesce((select active_batch_id::text from indicator_active_batches where indicator_id = 'e3-matchning-utbildning'), '')
    || ':' || coalesce((select active_batch_id::text from indicator_active_batches where indicator_id = 'e3-matchning-utbildning-kommun'), '')
    into v_marker;
  if v_marker <> ':' and v_marker is distinct from (select source_marker from agg_refresh_state where name = 'e3') then
    perform agg_refresh_e3(); v_done := v_done || '"e3"'::jsonb;
  end if;

  for r in select indicator_id, active_batch_id::text b from indicator_active_batches where indicator_id like 'af-%' order by indicator_id loop
    if r.b is distinct from (select source_marker from agg_refresh_state where name = 'af:' || r.indicator_id) then
      perform agg_refresh_af(r.indicator_id); v_done := v_done || to_jsonb(r.indicator_id);
    end if;
  end loop;

  select coalesce(string_agg(indicator_id || '=' || active_batch_id::text, ',' order by indicator_id), '')
    into v_marker from uka_active_batches;
  if v_marker <> '' and v_marker is distinct from (select source_marker from agg_refresh_state where name = 'uka') then
    perform agg_refresh_uka(); v_done := v_done || '"uka"'::jsonb;
  end if;
  return jsonb_build_object('refreshed', v_done);
end $function$;