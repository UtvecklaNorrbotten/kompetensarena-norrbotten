-- Förberäknade läsmodeller (aggregat) för Riket, alla län och alla kommuner.
-- Härledda tabeller: fylls enbart av agg_refresh_*-funktioner (service_role), läses publikt.

create table public.agg_refresh_state (
  name text primary key,
  scope text,
  row_count integer not null default 0,
  duration_ms integer,
  source_marker text,
  refreshed_at timestamptz not null default now()
);

create table public.agg_af_totals (
  indicator_id text not null references public.indicators(id),
  measure_code text not null,
  measure_label text,
  sex text not null default '',
  geo_code text not null,
  geo_level public.geo_level not null,
  period text not null,
  value double precision,
  primary key (indicator_id, measure_code, sex, geo_code, period)
);
create index agg_af_totals_geo_idx on public.agg_af_totals (geo_code, indicator_id, period);

create table public.agg_afr_ae_structure (
  geo_code text not null,
  geo_level public.geo_level not null,
  sni_avdelning text not null,
  sni2 text not null,
  anst_kl integer not null,
  arbetsstallen integer not null,
  primary key (geo_code, sni_avdelning, sni2, anst_kl)
);

create table public.agg_afr_je_sector (
  geo_code text not null,
  geo_level public.geo_level not null,
  priv_publ text not null,
  jurform text not null,
  anst_kl text not null,
  enheter integer not null,
  primary key (geo_code, priv_publ, jurform, anst_kl)
);

create table public.agg_afr_ae_dynamics (
  geo_code text not null,
  geo_level public.geo_level not null,
  month date not null,
  started integer not null default 0,
  ended integer not null default 0,
  primary key (geo_code, month)
);

create table public.agg_e3_matchning (
  geo_code text not null,
  geo_level public.geo_level not null,
  period text not null,
  utbildning_code text not null,
  utbildning_label text,
  sni_code text not null,
  sni_label text,
  helt double precision,
  delvis double precision,
  inte double precision,
  saknas double precision,
  totalt double precision,
  primary key (geo_code, period, utbildning_code, sni_code)
);
create index agg_e3_matchning_sni_idx on public.agg_e3_matchning (geo_code, period, sni_code);

do $$
declare t text;
begin
  foreach t in array array['agg_refresh_state','agg_af_totals','agg_afr_ae_structure','agg_afr_je_sector','agg_afr_ae_dynamics','agg_e3_matchning'] loop
    execute format('grant select on public.%I to anon, authenticated', t);
    execute format('grant all on public.%I to service_role', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "Publik läsning av aggregat" on public.%I for select to anon, authenticated using (true)', t);
  end loop;
end $$;

create or replace function public.agg_mark(p_name text, p_scope text, p_rows integer, p_started timestamptz, p_marker text)
returns void language sql security definer set search_path = public as $$
  insert into agg_refresh_state(name, scope, row_count, duration_ms, source_marker, refreshed_at)
  values (p_name, p_scope, p_rows, (extract(epoch from clock_timestamp() - p_started) * 1000)::int, p_marker, now())
  on conflict (name) do update set scope = excluded.scope, row_count = excluded.row_count,
    duration_ms = excluded.duration_ms, source_marker = excluded.source_marker, refreshed_at = excluded.refreshed_at;
$$;

-- AF: endast totalnivån (dimension_type = 'totalt') ur aktiv batch, per indikator.
create or replace function public.agg_refresh_af(p_indicator_id text)
returns jsonb language plpgsql security definer set search_path = public set statement_timeout = '300s' as $$
declare v_batch uuid; v_rows integer; v_t timestamptz := clock_timestamp();
begin
  if p_indicator_id !~ '^af-' then raise exception 'Endast AF-indikatorer'; end if;
  select active_batch_id into v_batch from indicator_active_batches where indicator_id = p_indicator_id;
  delete from agg_af_totals where indicator_id = p_indicator_id;
  if v_batch is null then
    perform agg_mark('af:' || p_indicator_id, p_indicator_id, 0, v_t, null);
    return jsonb_build_object('indicator_id', p_indicator_id, 'rows', 0);
  end if;
  insert into agg_af_totals(indicator_id, measure_code, measure_label, sex, geo_code, geo_level, period, value)
  select o.indicator_id, o.dimensions->>'measure_code', min(o.dimensions->>'measure_label'),
         coalesce(o.dimensions->>'sex', ''), o.geo_code, min(g.level), o.period, sum(o.value)
  from observations o join geographies g on g.code = o.geo_code
  where o.batch_id = v_batch and o.indicator_id = p_indicator_id
    and o.dimensions->>'dimension_type' = 'totalt'
  group by 1, 2, 4, 5, 7;
  get diagnostics v_rows = row_count;
  perform agg_mark('af:' || p_indicator_id, p_indicator_id, v_rows, v_t, v_batch::text);
  return jsonb_build_object('indicator_id', p_indicator_id, 'rows', v_rows);
end $$;

-- AFR: struktur, sektor och dynamik från publicerat aktuellt bestånd.
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
  select kommun, 'kommun', avd, sni2, kl, sum(n)::int from base where kommun is not null group by 1, 3, 4, 5
  union all select lan, 'län', avd, sni2, kl, sum(n)::int from base where lan is not null group by 1, 3, 4, 5
  union all select '00', 'riket', avd, sni2, kl, sum(n)::int from base group by 3, 4, 5;
  get diagnostics n1 = row_count;

  delete from agg_afr_je_sector where true;
  with base as (
    select lan_sate lan, kommun_sate kommun, coalesce(priv_publ, '?') pp, coalesce(jurform, '?') jf,
           coalesce(anst_kl, '0') kl, count(*)::int n
    from afr_je_current where in_source and ftg_stat = '1'
    group by 1, 2, 3, 4, 5
  )
  insert into agg_afr_je_sector(geo_code, geo_level, priv_publ, jurform, anst_kl, enheter)
  select kommun, 'kommun', pp, jf, kl, sum(n)::int from base where kommun is not null group by 1, 3, 4, 5
  union all select lan, 'län', pp, jf, kl, sum(n)::int from base where lan is not null group by 1, 3, 4, 5
  union all select '00', 'riket', pp, jf, kl, sum(n)::int from base group by 3, 4, 5;
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
  select kommun, 'kommun', m, sum(s)::int, sum(e)::int from base where kommun is not null group by 1, 3
  union all select lan, 'län', m, sum(s)::int, sum(e)::int from base where lan is not null group by 1, 3
  union all select '00', 'riket', m, sum(s)::int, sum(e)::int from base group by 3;
  get diagnostics n3 = row_count;

  perform agg_mark('afr', 'riket+län+kommun', n1 + n2 + n3, v_t, v_marker);
  return jsonb_build_object('structure', n1, 'sector', n2, 'dynamics', n3, 'source_date', v_marker);
end $$;

-- E3: kön = totalt, pivoterat till en rad per län/period/utbildning/bransch. Riket = summan av län.
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
  select o.geo_code, 'län', o.period, o.dimensions->>'utbildning_code', min(o.dimensions->>'utbildning_label'),
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
  select '00', 'riket', period, utbildning_code, min(utbildning_label), sni_code, min(sni_label),
         sum(helt), sum(delvis), sum(inte), sum(saknas), sum(totalt)
  from agg_e3_matchning where geo_level = 'län' group by 3, 4, 6;
  select count(*) into v_rows from agg_e3_matchning;
  perform agg_mark('e3', 'län+riket', v_rows, v_t, v_batch::text);
  return jsonb_build_object('rows', v_rows);
end $$;

revoke all on function public.agg_mark(text, text, integer, timestamptz, text) from public, anon, authenticated;
revoke all on function public.agg_refresh_af(text) from public, anon, authenticated;
revoke all on function public.agg_refresh_afr() from public, anon, authenticated;
revoke all on function public.agg_refresh_e3() from public, anon, authenticated;
grant execute on function public.agg_refresh_af(text) to service_role;
grant execute on function public.agg_refresh_afr() to service_role;
grant execute on function public.agg_refresh_e3() to service_role;