create or replace function public.afr_backfill_primary_sni(p_from_page integer, p_pages integer default 1000)
returns jsonb language plpgsql security definer set search_path = public set statement_timeout = '280s' as $$
declare v_n integer; v_total integer;
begin
  if p_pages < 1 or p_pages > 5000 then raise exception 'p_pages 1..5000' using errcode = 'invalid_parameter_value'; end if;
  update afr_je_current c set primary_sni = (
      select min(s.naringsgren collate "C") from afr_je_sni_current s where s.je_id = c.je_id and s.rangordning = 1)
  where c.ctid >= format('(%s,0)', p_from_page)::tid and c.ctid < format('(%s,0)', p_from_page + p_pages)::tid
    and c.primary_sni is null
    and exists (select 1 from afr_je_sni_current s where s.je_id = c.je_id and s.rangordning = 1);
  get diagnostics v_n = row_count;
  v_total := (pg_relation_size('public.afr_je_current') / 8192)::int;
  return jsonb_build_object('updated', v_n, 'next_page', p_from_page + p_pages, 'total_pages', v_total,
    'done', p_from_page + p_pages >= v_total);
end $$;

create or replace function public.afr_finalize_sync(p_sync_id uuid, p_stats jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = public set statement_timeout = '600s' as $$
declare
  v_sync afr_syncs%rowtype;
  v_je_prev integer; v_ae_prev integer; v_je_new integer; v_ae_new integer;
  v_je_changed integer; v_ae_changed integer; v_je_rm integer; v_ae_rm integer;
  v_je_after integer; v_ae_after integer; v_bad integer; v_types jsonb; v_stats jsonb; v_now timestamptz := now();
begin
  select * into v_sync from afr_syncs where id = p_sync_id for update;
  if not found then raise exception 'Synk % finns inte', p_sync_id using errcode = 'no_data_found'; end if;
  if v_sync.status = 'succeeded' then return jsonb_build_object('already_finalized', true, 'stats', v_sync.stats); end if;
  if v_sync.status <> 'receiving' then raise exception 'Synk har status %', v_sync.status using errcode = 'invalid_parameter_value'; end if;
  if v_sync.received_je_chunks <> v_sync.expected_je_chunks or v_sync.received_ae_chunks <> v_sync.expected_ae_chunks then
    raise exception 'Chunkar saknas (JE %/%, AE %/%)', v_sync.received_je_chunks, v_sync.expected_je_chunks,
      v_sync.received_ae_chunks, v_sync.expected_ae_chunks using errcode = 'invalid_parameter_value';
  end if;
  perform pg_advisory_xact_lock(hashtext('scb-afr'));

  if v_sync.mode = 'initial' then
    select coalesce(sum(row_count) filter (where entity='je'),0), coalesce(sum(row_count) filter (where entity='ae'),0)
      into v_je_new, v_ae_new from afr_sync_chunks where sync_id = p_sync_id;
    if v_je_new <> v_sync.je_source_count or v_ae_new <> v_sync.ae_source_count then
      raise exception 'Antal stämmer inte: JE % av %, AE % av %', v_je_new, v_sync.je_source_count, v_ae_new, v_sync.ae_source_count
        using errcode = 'invalid_parameter_value';
    end if;
    v_je_prev := 0; v_ae_prev := 0; v_je_changed := 0; v_ae_changed := 0; v_je_rm := 0; v_ae_rm := 0;
    v_je_after := v_je_new; v_ae_after := v_ae_new; v_types := '{}'::jsonb;
  else
    select count(*) into v_je_prev from afr_je_current where in_source;
    select count(*) into v_ae_prev from afr_ae_current where in_source;

    create temp table _je_up on commit drop as
      select s.key, s.payload p, s.row_hash, i.je_id, c.je_id is not null and c.in_source as was_present
      from afr_stage_records s
      left join afr_je_ident i on i.pe_org_nr = s.key
      left join afr_je_current c on c.je_id = i.je_id
      where s.sync_id = p_sync_id and s.entity = 'je' and s.op = 'upsert';
    create temp table _je_rm on commit drop as
      select s.key, c.je_id from afr_stage_records s
      left join afr_je_ident i on i.pe_org_nr = s.key
      left join afr_je_current c on c.je_id = i.je_id and c.in_source
      where s.sync_id = p_sync_id and s.entity = 'je' and s.op = 'remove';
    select count(*) into v_bad from _je_rm where je_id is null;
    if v_bad > 0 then raise exception '% bortfallna JE finns inte i aktuellt bestånd', v_bad using errcode = 'invalid_parameter_value'; end if;

    create temp table _ae_up on commit drop as
      select s.key, (s.key)::bigint cfar_nr, s.payload p, s.row_hash, c.cfar_nr is not null and c.in_source as was_present
      from afr_stage_records s left join afr_ae_current c on c.cfar_nr = (s.key)::bigint
      where s.sync_id = p_sync_id and s.entity = 'ae' and s.op = 'upsert';
    create temp table _ae_rm on commit drop as
      select s.key, c.cfar_nr from afr_stage_records s
      left join afr_ae_current c on c.cfar_nr = (s.key)::bigint and c.in_source
      where s.sync_id = p_sync_id and s.entity = 'ae' and s.op = 'remove';
    select count(*) into v_bad from _ae_rm where cfar_nr is null;
    if v_bad > 0 then raise exception '% bortfallna AE finns inte i aktuellt bestånd', v_bad using errcode = 'invalid_parameter_value'; end if;

    select count(*) filter (where not was_present), count(*) filter (where was_present) into v_je_new, v_je_changed from _je_up;
    select count(*) filter (where not was_present), count(*) filter (where was_present) into v_ae_new, v_ae_changed from _ae_up;
    select count(*) into v_je_rm from _je_rm;
    select count(*) into v_ae_rm from _ae_rm;

    if v_je_prev + v_je_new - v_je_rm <> v_sync.je_source_count then
      raise exception 'JE-balans stämmer inte: % + % − % ≠ %', v_je_prev, v_je_new, v_je_rm, v_sync.je_source_count using errcode = 'invalid_parameter_value';
    end if;
    if v_ae_prev + v_ae_new - v_ae_rm <> v_sync.ae_source_count then
      raise exception 'AE-balans stämmer inte: % + % − % ≠ %', v_ae_prev, v_ae_new, v_ae_rm, v_sync.ae_source_count using errcode = 'invalid_parameter_value';
    end if;
    if not v_sync.confirm_large_removal and
       (v_je_rm > greatest(1000, v_je_prev * 0.02) or v_ae_rm > greatest(1000, v_ae_prev * 0.02)) then
      raise exception 'Ovanligt stort bortfall (JE %, AE %) – kräver manuell kontroll', v_je_rm, v_ae_rm using errcode = 'invalid_parameter_value';
    end if;

    insert into afr_je_ident (pe_org_nr, org_nr)
      select key, nullif(p->>'org_nr','') from _je_up
      on conflict (pe_org_nr) do update set org_nr = coalesce(excluded.org_nr, afr_je_ident.org_nr);
    update _je_up u set je_id = i.je_id from afr_je_ident i where i.pe_org_nr = u.key and u.je_id is null;

    create temp table _je_types on commit drop as
      select u.je_id, array_remove(array[
        case when c.je_id is null then 'ny' when not c.in_source then 'återkommen' end,
        case when c.je_id is not null and (c.kommun_sate is distinct from u.p->>'kommun_sate' or c.lan_sate is distinct from u.p->>'lan_sate') then 'säte' end,
        case when c.je_id is not null and c.ae_ant is distinct from (u.p->>'ae_ant')::int then 'antal_arbetsställen' end,
        case when c.je_id is not null and c.anst_kl is distinct from u.p->>'anst_kl' then 'storlek' end,
        case when c.je_id is not null and (c.ftg_stat is distinct from u.p->>'ftg_stat' or c.arb_giv_stat is distinct from u.p->>'arb_giv_stat'
          or c.moms_stat is distinct from u.p->>'moms_stat' or c.f_skatt_stat is distinct from u.p->>'f_skatt_stat' or c.bol_stat is distinct from u.p->>'bol_stat') then 'status' end,
        case when c.je_id is not null and (c.jurform is distinct from u.p->>'jurform' or c.priv_publ is distinct from u.p->>'priv_publ') then 'juridisk_form' end,
        case when c.je_id is not null and (c.start_dat is distinct from (u.p->>'start_dat')::date or c.slut_dat is distinct from (u.p->>'slut_dat')::date
          or c.reg_dat is distinct from (u.p->>'reg_dat')::date) then 'datum' end,
        case when c.je_id is not null and (c.oms_ar is distinct from (u.p->>'oms_ar')::int or c.oms_kl is distinct from u.p->>'oms_kl') then 'omsättning' end,
        case when c.je_id is not null and c.ag_kat is distinct from u.p->>'ag_kat' then 'ägarkategori' end,
        case when c.je_id is not null and c.sektor is distinct from u.p->>'sektor' then 'sektor' end,
        case when c.je_id is not null and afr_canonical_sni(u.p->'sni') is distinct from coalesce((
          select string_agg(s.rangordning || ':' || s.naringsgren || ':' || coalesce(s.andel_procent::text,''), ';' order by s.rangordning, s.naringsgren collate "C")
          from afr_je_sni_current s where s.je_id = c.je_id), '') then 'SNI' end
      ]::text[], null) as change_types
      from _je_up u left join afr_je_current c on c.je_id = u.je_id;

    update afr_je_history h set valid_to = v_now from afr_je_current c
      where c.je_id in (select je_id from _je_up) and h.history_id = c.current_history_id and h.valid_to is null;

    create temp table _je_h on commit drop as
    with ins as (
      insert into afr_je_history (je_id, kommun_sate, lan_sate, ae_ant, anst_kl, ftg_stat, jurform, start_dat, slut_dat,
        reg_dat, oms_ar, oms_kl, ag_kat, arb_giv_stat, moms_stat, f_skatt_stat, bol_stat, priv_publ, sektor,
        row_hash, change_types, valid_from, sync_id, sni)
      select u.je_id, p->>'kommun_sate', p->>'lan_sate', (p->>'ae_ant')::int, p->>'anst_kl', p->>'ftg_stat', p->>'jurform',
        (p->>'start_dat')::date, (p->>'slut_dat')::date, (p->>'reg_dat')::date, (p->>'oms_ar')::int, p->>'oms_kl',
        p->>'ag_kat', p->>'arb_giv_stat', p->>'moms_stat', p->>'f_skatt_stat', p->>'bol_stat', p->>'priv_publ', p->>'sektor',
        u.row_hash, coalesce(t.change_types, array[]::text[]), v_now, p_sync_id, afr_sni_snapshot(u.p->'sni')
      from _je_up u join _je_types t on t.je_id = u.je_id
      returning history_id, je_id
    ) select ins.history_id, u.je_id, u.p, u.row_hash from ins join _je_up u on u.je_id = ins.je_id;

    insert into afr_je_current as c (je_id, kommun_sate, lan_sate, ae_ant, anst_kl, ftg_stat, jurform, start_dat, slut_dat,
      reg_dat, oms_ar, oms_kl, ag_kat, arb_giv_stat, moms_stat, f_skatt_stat, bol_stat, priv_publ, sektor,
      row_hash, in_source, first_seen_at, removed_observed_at, current_history_id, sync_id, primary_sni)
    select je_id, p->>'kommun_sate', p->>'lan_sate', (p->>'ae_ant')::int, p->>'anst_kl', p->>'ftg_stat', p->>'jurform',
      (p->>'start_dat')::date, (p->>'slut_dat')::date, (p->>'reg_dat')::date, (p->>'oms_ar')::int, p->>'oms_kl',
      p->>'ag_kat', p->>'arb_giv_stat', p->>'moms_stat', p->>'f_skatt_stat', p->>'bol_stat', p->>'priv_publ', p->>'sektor',
      row_hash, true, v_now, null, history_id, p_sync_id, afr_sni_primary(afr_sni_snapshot(p->'sni'))
    from _je_h
    on conflict (je_id) do update set kommun_sate = excluded.kommun_sate, lan_sate = excluded.lan_sate, ae_ant = excluded.ae_ant,
      anst_kl = excluded.anst_kl, ftg_stat = excluded.ftg_stat, jurform = excluded.jurform, start_dat = excluded.start_dat,
      slut_dat = excluded.slut_dat, reg_dat = excluded.reg_dat, oms_ar = excluded.oms_ar, oms_kl = excluded.oms_kl,
      ag_kat = excluded.ag_kat, arb_giv_stat = excluded.arb_giv_stat, moms_stat = excluded.moms_stat,
      f_skatt_stat = excluded.f_skatt_stat, bol_stat = excluded.bol_stat, priv_publ = excluded.priv_publ, sektor = excluded.sektor,
      row_hash = excluded.row_hash, in_source = true, removed_observed_at = null,
      current_history_id = excluded.current_history_id, sync_id = excluded.sync_id, primary_sni = excluded.primary_sni;

    delete from afr_je_sni_current where je_id in (select je_id from _je_h);
    insert into afr_je_sni_current (je_id, rangordning, naringsgren, andel_procent, avdelnings_kod)
      select h.je_id, (e->>'r')::int, e->>'kod', (e->>'andel')::int, e->>'avd' from _je_h h, jsonb_array_elements(coalesce(h.p->'sni','[]'::jsonb)) e;

    update afr_je_history h set valid_to = v_now from afr_je_current c
      where c.je_id in (select je_id from _je_rm) and h.history_id = c.current_history_id and h.valid_to is null;
    create temp table _je_rh on commit drop as
    with ins as (
      insert into afr_je_history (je_id, kommun_sate, lan_sate, ae_ant, anst_kl, ftg_stat, jurform, start_dat, slut_dat,
        reg_dat, oms_ar, oms_kl, ag_kat, arb_giv_stat, moms_stat, f_skatt_stat, bol_stat, priv_publ, sektor,
        row_hash, change_types, in_source, valid_from, sync_id, sni)
      select c.je_id, c.kommun_sate, c.lan_sate, c.ae_ant, c.anst_kl, c.ftg_stat, c.jurform, c.start_dat, c.slut_dat,
        c.reg_dat, c.oms_ar, c.oms_kl, c.ag_kat, c.arb_giv_stat, c.moms_stat, c.f_skatt_stat, c.bol_stat, c.priv_publ, c.sektor,
        c.row_hash, array['ej_längre_observerad'], false, v_now, p_sync_id,
        (select ph.sni from afr_je_history ph where ph.history_id = c.current_history_id)
      from afr_je_current c where c.je_id in (select je_id from _je_rm)
      returning history_id, je_id
    ) select * from ins;
    update afr_je_current c set in_source = false, removed_observed_at = v_now, current_history_id = r.history_id, sync_id = p_sync_id
      from _je_rh r where r.je_id = c.je_id;

    insert into afr_je_ident (pe_org_nr)
      select distinct p->>'pe_org_nr' from _ae_up where p->>'pe_org_nr' is not null on conflict (pe_org_nr) do nothing;

    create temp table _ae_x on commit drop as
      select u.*, i.je_id as new_je_id from _ae_up u left join afr_je_ident i on i.pe_org_nr = u.p->>'pe_org_nr';

    create temp table _ae_types on commit drop as
      select x.cfar_nr, array_remove(array[
        case when c.cfar_nr is null then 'ny' when not c.in_source then 'återkommen' end,
        case when c.cfar_nr is not null and c.je_id is distinct from x.new_je_id then 'juridisk_enhet' end,
        case when c.cfar_nr is not null and (c.ae_stat is distinct from (x.p->>'ae_stat')::int or c.hj_verks_je is distinct from (x.p->>'hj_verks_je')::int
          or c.ae_typ is distinct from (x.p->>'ae_typ')::int) then 'status' end,
        case when c.cfar_nr is not null and c.anst_kl is distinct from (x.p->>'anst_kl')::int then 'storlek' end,
        case when c.cfar_nr is not null and (c.start_dat is distinct from (x.p->>'start_dat')::date or c.slut_dat is distinct from (x.p->>'slut_dat')::date) then 'datum' end,
        case when c.cfar_nr is not null and (c.lan is distinct from x.p->>'lan' or c.kommun is distinct from x.p->>'kommun'
          or c.nord_sw is distinct from (x.p->>'nord_sw')::int or c.ost_sw is distinct from (x.p->>'ost_sw')::int
          or c.tat_sma_typ_kod is distinct from x.p->>'tat_sma_typ_kod' or c.tat_ort_sma_ort_kod is distinct from x.p->>'tat_ort_sma_ort_kod'
          or c.tat_ort_sma_ort_ben is distinct from x.p->>'tat_ort_sma_ort_ben') then 'geografi' end,
        case when c.cfar_nr is not null and afr_canonical_sni(x.p->'sni') is distinct from coalesce((
          select string_agg(s.rangordning || ':' || s.naringsgren || ':' || coalesce(s.andel_procent::text,''), ';' order by s.rangordning, s.naringsgren collate "C")
          from afr_ae_sni_current s where s.cfar_nr = c.cfar_nr), '') then 'SNI' end
      ]::text[], null) as change_types
      from _ae_x x left join afr_ae_current c on c.cfar_nr = x.cfar_nr;

    update afr_ae_history h set valid_to = v_now from afr_ae_current c
      where c.cfar_nr in (select cfar_nr from _ae_x) and h.history_id = c.current_history_id and h.valid_to is null;

    create temp table _ae_h on commit drop as
    with ins as (
      insert into afr_ae_history (cfar_nr, je_id, ae_stat, anst_kl, hj_verks_je, ae_typ, start_dat, slut_dat, lan, kommun,
        nord_sw, ost_sw, tat_sma_typ_kod, tat_ort_sma_ort_kod, tat_ort_sma_ort_ben, row_hash, change_types, valid_from, sync_id, sni)
      select x.cfar_nr, x.new_je_id, (p->>'ae_stat')::int, (p->>'anst_kl')::int, (p->>'hj_verks_je')::int, (p->>'ae_typ')::int,
        (p->>'start_dat')::date, (p->>'slut_dat')::date, p->>'lan', p->>'kommun', (p->>'nord_sw')::int, (p->>'ost_sw')::int,
        p->>'tat_sma_typ_kod', p->>'tat_ort_sma_ort_kod', p->>'tat_ort_sma_ort_ben', x.row_hash,
        coalesce(t.change_types, array[]::text[]), v_now, p_sync_id, afr_sni_snapshot(x.p->'sni')
      from _ae_x x join _ae_types t on t.cfar_nr = x.cfar_nr
      returning history_id, cfar_nr
    ) select ins.history_id, x.cfar_nr, x.new_je_id, x.p, x.row_hash from ins join _ae_x x on x.cfar_nr = ins.cfar_nr;

    insert into afr_ae_current as c (cfar_nr, je_id, ae_stat, anst_kl, hj_verks_je, ae_typ, start_dat, slut_dat, lan, kommun,
      nord_sw, ost_sw, tat_sma_typ_kod, tat_ort_sma_ort_kod, tat_ort_sma_ort_ben, row_hash, in_source, first_seen_at,
      removed_observed_at, current_history_id, sync_id, primary_sni)
    select cfar_nr, new_je_id, (p->>'ae_stat')::int, (p->>'anst_kl')::int, (p->>'hj_verks_je')::int, (p->>'ae_typ')::int,
      (p->>'start_dat')::date, (p->>'slut_dat')::date, p->>'lan', p->>'kommun', (p->>'nord_sw')::int, (p->>'ost_sw')::int,
      p->>'tat_sma_typ_kod', p->>'tat_ort_sma_ort_kod', p->>'tat_ort_sma_ort_ben', row_hash, true, v_now, null, history_id, p_sync_id, afr_sni_primary(afr_sni_snapshot(p->'sni'))
    from _ae_h
    on conflict (cfar_nr) do update set je_id = excluded.je_id, ae_stat = excluded.ae_stat, anst_kl = excluded.anst_kl,
      hj_verks_je = excluded.hj_verks_je, ae_typ = excluded.ae_typ, start_dat = excluded.start_dat, slut_dat = excluded.slut_dat,
      lan = excluded.lan, kommun = excluded.kommun, nord_sw = excluded.nord_sw, ost_sw = excluded.ost_sw,
      tat_sma_typ_kod = excluded.tat_sma_typ_kod, tat_ort_sma_ort_kod = excluded.tat_ort_sma_ort_kod,
      tat_ort_sma_ort_ben = excluded.tat_ort_sma_ort_ben, row_hash = excluded.row_hash, in_source = true,
      removed_observed_at = null, current_history_id = excluded.current_history_id, sync_id = excluded.sync_id, primary_sni = excluded.primary_sni;

    delete from afr_ae_sni_current where cfar_nr in (select cfar_nr from _ae_h);
    insert into afr_ae_sni_current (cfar_nr, rangordning, naringsgren, andel_procent, avdelnings_kod)
      select h.cfar_nr, (e->>'r')::int, e->>'kod', (e->>'andel')::int, e->>'avd' from _ae_h h, jsonb_array_elements(coalesce(h.p->'sni','[]'::jsonb)) e;

    update afr_ae_history h set valid_to = v_now from afr_ae_current c
      where c.cfar_nr in (select cfar_nr from _ae_rm) and h.history_id = c.current_history_id and h.valid_to is null;
    create temp table _ae_rh on commit drop as
    with ins as (
      insert into afr_ae_history (cfar_nr, je_id, ae_stat, anst_kl, hj_verks_je, ae_typ, start_dat, slut_dat, lan, kommun,
        nord_sw, ost_sw, tat_sma_typ_kod, tat_ort_sma_ort_kod, tat_ort_sma_ort_ben, row_hash, change_types, in_source, valid_from, sync_id, sni)
      select c.cfar_nr, c.je_id, c.ae_stat, c.anst_kl, c.hj_verks_je, c.ae_typ, c.start_dat, c.slut_dat, c.lan, c.kommun,
        c.nord_sw, c.ost_sw, c.tat_sma_typ_kod, c.tat_ort_sma_ort_kod, c.tat_ort_sma_ort_ben, c.row_hash,
        array['ej_längre_observerad'], false, v_now, p_sync_id,
        (select ph.sni from afr_ae_history ph where ph.history_id = c.current_history_id)
      from afr_ae_current c where c.cfar_nr in (select cfar_nr from _ae_rm)
      returning history_id, cfar_nr
    ) select * from ins;
    update afr_ae_current c set in_source = false, removed_observed_at = v_now, current_history_id = r.history_id, sync_id = p_sync_id
      from _ae_rh r where r.cfar_nr = c.cfar_nr;

    select count(*) into v_je_after from afr_je_current where in_source;
    select count(*) into v_ae_after from afr_ae_current where in_source;
    if v_je_after <> v_sync.je_source_count or v_ae_after <> v_sync.ae_source_count then
      raise exception 'Slutkontroll misslyckades: JE % (källa %), AE % (källa %)', v_je_after, v_sync.je_source_count,
        v_ae_after, v_sync.ae_source_count using errcode = 'invalid_parameter_value';
    end if;

    select jsonb_build_object(
      'je', coalesce((select jsonb_object_agg(t, n) from (select t, count(*) n from _je_types, unnest(change_types) t group by t) a), '{}'::jsonb),
      'ae', coalesce((select jsonb_object_agg(t, n) from (select t, count(*) n from _ae_types, unnest(change_types) t group by t) b), '{}'::jsonb)
    ) into v_types;

    delete from afr_stage_records where sync_id = p_sync_id;
  end if;

  v_stats := coalesce(v_sync.stats, '{}'::jsonb) || coalesce(p_stats, '{}'::jsonb) || jsonb_build_object(
    'mode', v_sync.mode, 'source_date', v_sync.source_date, 'api_version', v_sync.api_version,
    'je_source_count', v_sync.je_source_count, 'ae_source_count', v_sync.ae_source_count,
    'je_previous', v_je_prev, 'ae_previous', v_ae_prev,
    'je_new', v_je_new, 'ae_new', v_ae_new, 'je_changed', v_je_changed, 'ae_changed', v_ae_changed,
    'je_removed', v_je_rm, 'ae_removed', v_ae_rm,
    'je_unchanged', v_je_after - v_je_new - v_je_changed, 'ae_unchanged', v_ae_after - v_ae_new - v_ae_changed,
    'change_types', v_types);

  update afr_syncs set status = 'succeeded', finalized_at = v_now, last_activity_at = v_now, stats = v_stats, error_message = null
    where id = p_sync_id;
  delete from afr_sync_chunks where sync_id = p_sync_id;

  update data_source_runs set status = 'succeeded', finished_at = v_now, error_message = null,
    rows_affected = v_je_new + v_je_changed + v_je_rm + v_ae_new + v_ae_changed + v_ae_rm,
    details = coalesce(details, '{}'::jsonb) || v_stats
  where id = v_sync.run_id;

  insert into data_source_state (source_id, latest_available_period, latest_successful_period, last_checked_at,
    last_successful_at, last_status, last_error, details, updated_at)
  values ('scb-afr', v_sync.source_date, v_sync.source_date, v_now, v_now, 'succeeded', null, v_stats, v_now)
  on conflict (source_id) do update set latest_available_period = excluded.latest_available_period,
    latest_successful_period = excluded.latest_successful_period, last_checked_at = excluded.last_checked_at,
    last_successful_at = excluded.last_successful_at, last_status = 'succeeded', last_error = null,
    details = excluded.details, updated_at = excluded.updated_at;

  return jsonb_build_object('already_finalized', false, 'stats', v_stats);
end $$;