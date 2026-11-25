-- Publika, förberäknade AF-grupper; råa observationsrader läses aldrig av sidan.
create table public.agg_af_duration (
  geo_code text not null references public.geographies(code),
  period text not null,
  dimension_type text not null,
  dimension_value text not null,
  total double precision,
  over6 double precision,
  over12 double precision,
  over24 double precision,
  lower6 boolean not null default false,
  lower12 boolean not null default false,
  lower24 boolean not null default false,
  primary key (geo_code, dimension_type, dimension_value, period)
);
alter table public.agg_af_duration enable row level security;
create policy "Public AF duration aggregates" on public.agg_af_duration for select to anon, authenticated using (true);
grant select on public.agg_af_duration to anon, authenticated;
grant all on public.agg_af_duration to service_role;
create index agg_af_duration_comparison on public.agg_af_duration(period, dimension_type, dimension_value);

create or replace function public.agg_refresh_af_duration()
returns jsonb language plpgsql security definer set search_path = public set statement_timeout = '300s' set work_mem = '32MB' as $$
declare v_marker text; v_rows integer; v_t timestamptz := clock_timestamp();
begin
  perform pg_advisory_xact_lock(hashtext('agg_af_duration'));
  -- replace_period changes observations in place: batch UUID alone misses monthly imports/revisions.
  select string_agg(b.indicator_id || ':' || b.active_batch_id::text || ':' || coalesce(m.updated_at::text, ''), ',' order by b.indicator_id)
    into v_marker from indicator_active_batches b left join indicator_metadata m using (indicator_id)
    where b.indicator_id in ('af-arbetssokande', 'af-tid-utan-arbete');
  if v_marker is null or v_marker = (select source_marker from agg_refresh_state where name = 'af-duration') then
    return jsonb_build_object('status', 'no_change');
  end if;
  delete from agg_af_duration;
  with s as (
    select o.geo_code, o.period, o.dimensions->>'dimension_type' dt,
      o.dimensions->>'dimension_value' dv, o.dimensions->>'sex' sex, o.value
    from observations o join indicator_active_batches b on b.indicator_id = o.indicator_id and b.active_batch_id = o.batch_id
    where o.indicator_id = 'af-arbetssokande' and o.dimensions->>'measure_code' = 'INSAL'
  ), denominators as (
    -- Dimensionerna är alternativa uppdelningar: summera aldrig mellan dem.
    select geo_code, period, dt, dv, case when count(*) = count(value) then sum(value) end total from s
      group by geo_code, period, dt, dv
    union all
    select geo_code, period, 'totalt', 'Totalt', case when count(*) = count(value) then sum(value) end from s where dt = 'ålder'
      group by geo_code, period
    union all
    select geo_code, period, 'kön', sex, case when count(*) = count(value) then sum(value) end from s where dt = 'ålder'
      group by geo_code, period, sex
  ), d as (
    select o.geo_code, o.period, o.dimensions->>'dimension_type' dt, o.dimensions->>'dimension_value' dv,
      -- Riket använder UAxx, län/kommun KUAxx. Samma definition, olika källkod.
      regexp_replace(o.dimensions->>'measure_code', '^K', '') mc,
      o.value, coalesce((o.dimensions->>'value_is_lower_bound')::boolean, false) lb
    from observations o join indicator_active_batches b on b.indicator_id = o.indicator_id and b.active_batch_id = o.batch_id
    where o.indicator_id = 'af-tid-utan-arbete'
  ), p as (
    select geo_code, period, dt, dv,
      max(value) filter (where mc = 'UA06') over6,
      max(value) filter (where mc = 'UA12') over12,
      max(value) filter (where mc = 'UA24') over24,
      coalesce(bool_or(lb) filter (where mc = 'UA06'), false) lower6,
      coalesce(bool_or(lb) filter (where mc = 'UA12'), false) lower12,
      coalesce(bool_or(lb) filter (where mc = 'UA24'), false) lower24
    from d group by geo_code, period, dt, dv
  )
  insert into agg_af_duration
  select p.geo_code, p.period, p.dt, p.dv, n.total, p.over6, p.over12, p.over24, p.lower6, p.lower12, p.lower24
    from p left join denominators n on n.geo_code = p.geo_code and n.period = p.period and n.dt = p.dt and n.dv = p.dv;
  get diagnostics v_rows = row_count;
  perform agg_mark('af-duration', 'AF tid utan arbete och inskrivna arbetslösa', v_rows, v_t, v_marker);
  return jsonb_build_object('rows', v_rows, 'source_marker', v_marker);
end $$;
revoke all on function public.agg_refresh_af_duration() from public, anon, authenticated;
grant execute on function public.agg_refresh_af_duration() to service_role;
-- Egen begränsad omräkning bevarar övriga källors befintliga scheman.
select cron.schedule('agg-refresh-af-duration', '27 * * * *', $$SET statement_timeout='10min'; select public.agg_refresh_af_duration()$$);
