-- Länsbatchen från 2026-09-22 saknar utbildning_indelning_code i dimensions;
-- behandla saknat fält som 'grupp' så läns- och riksaggregat räknas fram igen.
create or replace function public.agg_refresh_e3()
returns jsonb language plpgsql security definer set search_path = public set statement_timeout = '600s' as $$
declare v_batch uuid; v_kommun uuid; v_marker text; v_rows int; v_t timestamptz := clock_timestamp();
begin
  select active_batch_id into v_batch from indicator_active_batches where indicator_id = 'e3-matchning-utbildning';
  select active_batch_id into v_kommun from indicator_active_batches where indicator_id = 'e3-matchning-utbildning-kommun';
  v_marker := coalesce(v_batch::text, '') || ':' || coalesce(v_kommun::text, '');
  delete from agg_e3_matchning where true;
  if v_batch is null and v_kommun is null then
    perform agg_mark('e3', 'län+riket+kommun', 0, v_t, null);
    return jsonb_build_object('rows', 0);
  end if;
  insert into agg_e3_matchning(geo_code, geo_level, period, utbildning_code, utbildning_label, sni_code, sni_label,
                               helt, delvis, inte, saknas, totalt)
  select o.geo_code, 'län'::public.geo_level, o.period, o.dimensions->>'utbildning_code', min(o.dimensions->>'utbildning_label'),
         o.dimensions->>'sni2007_code', min(o.dimensions->>'sni2007_label'),
         sum(o.value) filter (where o.dimensions->>'contents_code' = '000008QQ'),
         sum(o.value) filter (where o.dimensions->>'contents_code' = '000008QP'),
         sum(o.value) filter (where o.dimensions->>'contents_code' = '000008QR'),
         sum(o.value) filter (where o.dimensions->>'contents_code' = '000008QS'),
         sum(o.value) filter (where o.dimensions->>'contents_code' = '000008QT')
  from observations o
  where o.batch_id = v_batch and o.indicator_id = 'e3-matchning-utbildning'
    and o.dimensions->>'kon_alder_fodelseland_code' = 'totalt'
    and coalesce(o.dimensions->>'utbildning_indelning_code', 'grupp') = 'grupp'
  group by 1, 3, 4, 6;
  insert into agg_e3_matchning(geo_code, geo_level, period, utbildning_code, utbildning_label, sni_code, sni_label,
                               helt, delvis, inte, saknas, totalt)
  select '00', 'riket'::public.geo_level, period, utbildning_code, min(utbildning_label), sni_code, min(sni_label),
         sum(helt), sum(delvis), sum(inte), sum(saknas), sum(totalt)
  from agg_e3_matchning where geo_level = 'län' group by 3, 4, 6;
  -- Kommuner hämtas direkt från SCB; de summeras inte till län eller Riket.
  insert into agg_e3_matchning(geo_code, geo_level, period, utbildning_code, utbildning_label, sni_code, sni_label,
                               helt, delvis, inte, saknas, totalt, forvarvsgrad, matchad_forvarvsgrad)
  select o.geo_code, 'kommun'::public.geo_level, o.period,
         o.dimensions->>'utbildning_code', min(o.dimensions->>'utbildning_label'),
         o.dimensions->>'sni2007_code', min(o.dimensions->>'sni2007_label'),
         max(o.value) filter (where o.dimensions->>'contents_code' = '000008QQ'),
         max(o.value) filter (where o.dimensions->>'contents_code' = '000008QP'),
         max(o.value) filter (where o.dimensions->>'contents_code' = '000008QR'),
         max(o.value) filter (where o.dimensions->>'contents_code' = '000008QS'),
         max(o.value) filter (where o.dimensions->>'contents_code' = '000008QT'),
         max(o.value) filter (where o.dimensions->>'contents_code' = '000008QU'),
         max(o.value) filter (where o.dimensions->>'contents_code' = '000008QV')
  from observations o
  where o.batch_id = v_kommun and o.indicator_id = 'e3-matchning-utbildning-kommun'
    and o.dimensions->>'utbildning_indelning_code' = 'grupp'
    and o.dimensions->>'kon_alder_fodelseland_code' = 'totalt'
  group by 1, 3, 4, 6;
  select count(*) into v_rows from agg_e3_matchning;
  perform agg_mark('e3', 'län+riket+kommun', v_rows, v_t, v_marker);
  return jsonb_build_object('rows', v_rows);
end $$;