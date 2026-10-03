alter table public.agg_afr_ae_structure drop constraint agg_afr_ae_structure_pkey,
  add primary key (geo_level, geo_code, sni_avdelning, sni2, anst_kl);
alter table public.agg_afr_je_sector drop constraint agg_afr_je_sector_pkey,
  add primary key (geo_level, geo_code, priv_publ, jurform, anst_kl);
alter table public.agg_afr_ae_dynamics drop constraint agg_afr_ae_dynamics_pkey,
  add primary key (geo_level, geo_code, month);

-- Totalnivå per AF-indikator: 'totalt' om den finns, annars summan över en fullständig uppdelning.
-- Rader uppdelade på kön får dessutom en könsoberoende summa (sex = '').
create or replace function public.agg_refresh_af(p_indicator_id text)
returns jsonb language plpgsql security definer set search_path = public set statement_timeout = '300s' as $$
declare v_batch uuid; v_rows integer; v_t timestamptz := clock_timestamp(); v_dt text;
begin
  if p_indicator_id !~ '^af-' then raise exception 'Endast AF-indikatorer'; end if;
  v_dt := case p_indicator_id
    when 'af-arbetssokande' then 'ålder'
    when 'af-svag-konkurrensformaga' then 'kön'
    when 'af-yrkesomrade' then 'yrkesområde'
    else 'totalt' end;
  select active_batch_id into v_batch from indicator_active_batches where indicator_id = p_indicator_id;
  delete from agg_af_totals where indicator_id = p_indicator_id;
  if v_batch is null then
    perform agg_mark('af:' || p_indicator_id, p_indicator_id, 0, v_t, null);
    return jsonb_build_object('indicator_id', p_indicator_id, 'rows', 0);
  end if;
  with base as (
    select o.dimensions->>'measure_code' mc, min(o.dimensions->>'measure_label') ml,
           coalesce(o.dimensions->>'sex', '') sex, o.geo_code, o.period, sum(o.value) v
    from observations o
    where o.batch_id = v_batch and o.indicator_id = p_indicator_id
      and o.dimensions->>'dimension_type' = v_dt
    group by 1, 3, 4, 5
  ), withtotal as (
    select mc, ml, sex, geo_code, period, v from base
    union all
    select mc, min(ml), '', geo_code, period, sum(v) from base
    where sex in ('K', 'M')
      and not exists (select 1 from base b2 where b2.sex = '' limit 1)
    group by mc, geo_code, period
  )
  insert into agg_af_totals(indicator_id, measure_code, measure_label, sex, geo_code, geo_level, period, value)
  select p_indicator_id, w.mc, w.ml, w.sex, w.geo_code, g.level, w.period, w.v
  from withtotal w join geographies g on g.code = w.geo_code;
  get diagnostics v_rows = row_count;
  perform agg_mark('af:' || p_indicator_id, p_indicator_id || ' (' || v_dt || ')', v_rows, v_t, v_batch::text);
  return jsonb_build_object('indicator_id', p_indicator_id, 'rows', v_rows, 'basis', v_dt);
end $$;