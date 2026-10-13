-- Store complete source JSON only in observations.dimensions.row_json.
-- Keep the analytic aggregate as a compact projection instead of duplicating
-- each complete original row.
alter table public.agg_af_yrkesbarometer drop column if exists original;

create or replace function public.refresh_agg_af_yrkesbarometer()
returns void language plpgsql security definer set search_path = public as $$
declare v_batch uuid;
begin
  select active_batch_id into v_batch
  from public.indicator_active_batches where indicator_id = 'af-yrkesbarometern';
  if v_batch is null then return; end if;

  delete from public.agg_af_yrkesbarometer;
  insert into public.agg_af_yrkesbarometer (
    period, geo_code, yb_concept_id, jobbmojligheter, rekryteringssituation,
    prognos, hogsta_bedomningsniva, delvis_helt, yrke, ssyk, source_batch_id)
  select o.period, o.geo_code, o.dimensions->>'yb_concept_id',
    j.original->>'jobbmojligheter', j.original->>'rekryteringssituation',
    j.original->>'prognos', j.original->>'hogsta_bedomningsniva',
    j.original->>'delvis_helt',
    coalesce(j.original->>'yb_yrke', j.original->>'yrke'),
    j.original->'ssyk', v_batch
  from public.observations o
  cross join lateral (
    select (o.dimensions->>'row_json')::jsonb as original
  ) j
  where o.indicator_id = 'af-yrkesbarometern'
    and o.batch_id = v_batch;
end;
$$;
revoke all on function public.refresh_agg_af_yrkesbarometer() from public, anon, authenticated;
grant execute on function public.refresh_agg_af_yrkesbarometer() to service_role;
notify pgrst, 'reload schema';
