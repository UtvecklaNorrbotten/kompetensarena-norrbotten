create or replace function public.agg_refresh_afr()
returns jsonb language plpgsql security definer set search_path = public set statement_timeout = '600s' as $$
declare v_t timestamptz := clock_timestamp(); v_marker text; n1 int; n2 int; n3 int;
begin
  select source_date into v_marker from afr_syncs where status = 'succeeded' order by finalized_at desc nulls last limit 1;

  delete from agg_afr_ae_structure where true;
  with base as (
    select a.lan, a.kommun, coalesce(s.avdelnings_kod, '?') avd,
           coalesce(left(a.primary_sni, 2), '00') sni2, coalesce(a.anst_kl, 0) kl, count(*)::int n
    from afr_ae_current a
    left join afr_ae_sni_current s on s.cfar_nr = a.cfar_nr and s.rangordning = 1
    where a.in_source and a.ae_stat = 1
    group by 1, 2, 3, 4, 5
  )
  insert into agg_afr_ae_structure(geo_code, geo_level, sni_avdelning, sni2, anst_kl, arbetsstallen)
  select kommun, 'kommun'::public.geo_level, avd, sni2, kl, sum(n)::int from base where kommun is not null group by 1, 3, 4, 5
  union all select lan, 'län'::public.geo_level, avd, sni2, kl, sum(n)::int from base where lan is not null group by 1, 3, 4, 5
  union all select '00', 'riket'::public.geo_level, avd, sni2, kl, sum(n)::int from base group by 3, 4, 5;
  get diagnostics n1 = row_count;

  delete from agg_afr_je_sector where true;
  with base as (
    select lan_sate lan, kommun_sate kommun, coalesce(priv_publ, '?') pp, coalesce(jurform, '?') jf,
           coalesce(anst_kl, '0') kl, count(*)::int n
    from afr_je_current where in_source and ftg_stat = '1'
    group by 1, 2, 3, 4, 5
  )
  insert into agg_afr_je_sector(geo_code, geo_level, priv_publ, jurform, anst_kl, enheter)
  select kommun, 'kommun'::public.geo_level, pp, jf, kl, sum(n)::int from base where kommun is not null group by 1, 3, 4, 5
  union all select lan, 'län'::public.geo_level, pp, jf, kl, sum(n)::int from base where lan is not null group by 1, 3, 4, 5
  union all select '00', 'riket'::public.geo_level, pp, jf, kl, sum(n)::int from base group by 3, 4, 5;
  get diagnostics n2 = row_count;

  delete from agg_afr_ae_dynamics where true;
  with ev as (
    select lan, kommun, date_trunc('month', start_dat)::date m, 1 s, 0 e from afr_ae_current
      where in_source and start_dat >= date '2000-01-01'
    union all
    select lan, kommun, date_trunc('month', slut_dat)::date, 0, 1 from afr_ae_current
      where in_source and slut_dat >= date '2000-01-01'
  ), base as (
    select lan, kommun, m, sum(s)::int s, sum(e)::int e from ev group by 1, 2, 3
  )
  insert into agg_afr_ae_dynamics(geo_code, geo_level, month, started, ended)
  select kommun, 'kommun'::public.geo_level, m, sum(s)::int, sum(e)::int from base where kommun is not null group by 1, 3
  union all select lan, 'län'::public.geo_level, m, sum(s)::int, sum(e)::int from base where lan is not null group by 1, 3
  union all select '00', 'riket'::public.geo_level, m, sum(s)::int, sum(e)::int from base group by 3;
  get diagnostics n3 = row_count;

  perform agg_mark('afr', 'riket+län+kommun', n1 + n2 + n3, v_t, v_marker);
  return jsonb_build_object('structure', n1, 'sector', n2, 'dynamics', n3, 'source_date', v_marker);
end $$;

create or replace function public.agg_refresh_e3()
returns jsonb language plpgsql security definer set search_path = public set statement_timeout = '600s' as $$
declare v_batch uuid; v_rows int; v_t timestamptz := clock_timestamp();
begin
  select active_batch_id into v_batch from indicator_active_batches where indicator_id = 'e3-matchning-utbildning';
  delete from agg_e3_matchning where true;
  if v_batch is null then
    perform agg_mark('e3', 'län+riket', 0, v_t, null);
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
  group by 1, 3, 4, 6;
  insert into agg_e3_matchning(geo_code, geo_level, period, utbildning_code, utbildning_label, sni_code, sni_label,
                               helt, delvis, inte, saknas, totalt)
  select '00', 'riket'::public.geo_level, period, utbildning_code, min(utbildning_label), sni_code, min(sni_label),
         sum(helt), sum(delvis), sum(inte), sum(saknas), sum(totalt)
  from agg_e3_matchning where geo_level = 'län' group by 3, 4, 6;
  select count(*) into v_rows from agg_e3_matchning;
  perform agg_mark('e3', 'län+riket', v_rows, v_t, v_batch::text);
  return jsonb_build_object('rows', v_rows);
end $$;