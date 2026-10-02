CREATE OR REPLACE FUNCTION public.afr_store_chunk(p_sync_id uuid, p_entity text, p_chunk_index integer, p_records jsonb, p_removed jsonb, p_checksum text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' SET statement_timeout TO '300s'
AS $function$
declare
  v_sync afr_syncs%rowtype; v_existing afr_sync_chunks%rowtype;
  v_expected integer; v_rows integer; v_removed integer; v_bad text;
begin
  select * into v_sync from afr_syncs where id = p_sync_id for update;
  if not found then raise exception 'Synk % finns inte', p_sync_id using errcode = 'no_data_found'; end if;
  if v_sync.status <> 'receiving' then raise exception 'Synk har status %', v_sync.status using errcode = 'invalid_parameter_value'; end if;
  if p_entity not in ('je','ae') then raise exception 'Okänd entitet' using errcode = 'invalid_parameter_value'; end if;
  v_expected := case when p_entity = 'je' then v_sync.expected_je_chunks else v_sync.expected_ae_chunks end;
  if p_chunk_index < 0 or p_chunk_index >= v_expected then
    raise exception 'chunk_index % utanför 0..%', p_chunk_index, v_expected - 1 using errcode = 'invalid_parameter_value';
  end if;

  select * into v_existing from afr_sync_chunks where sync_id = p_sync_id and entity = p_entity and chunk_index = p_chunk_index;
  if found then
    if v_existing.checksum = p_checksum then
      update afr_syncs set last_activity_at = now() where id = p_sync_id;
      return jsonb_build_object('duplicate', true, 'chunk_index', p_chunk_index, 'entity', p_entity);
    end if;
    raise exception 'Chunk % finns redan med annat innehåll', p_chunk_index using errcode = 'unique_violation';
  end if;

  p_records := coalesce(p_records, '[]'::jsonb);
  p_removed := coalesce(p_removed, '[]'::jsonb);
  v_rows := jsonb_array_length(p_records);
  v_removed := jsonb_array_length(p_removed);

  if p_entity = 'je' then
    select r->>'key' into v_bad from jsonb_array_elements(p_records) r
    where r->>'key' is null or r->>'hash' is distinct from afr_hash(afr_je_canonical(r)) limit 1;
  else
    select coalesce(r->>'key','(saknas)') into v_bad from jsonb_array_elements(p_records) r
    where r->>'key' is null or (r->>'key') !~ '^[0-9]+$' or r->>'hash' is distinct from afr_hash(afr_ae_canonical(r)) limit 1;
  end if;
  if v_bad is not null then raise exception 'Hash eller nyckel stämmer inte för post %', v_bad using errcode = 'invalid_parameter_value'; end if;

  if v_sync.mode = 'initial' then
    if v_removed > 0 then raise exception 'Första laddningen kan inte ha bortfall' using errcode = 'invalid_parameter_value'; end if;

    if p_entity = 'je' then
      insert into afr_je_ident (pe_org_nr, org_nr)
      select r->>'key', nullif(r->>'org_nr','') from jsonb_array_elements(p_records) r
      on conflict (pe_org_nr) do update set org_nr = coalesce(excluded.org_nr, afr_je_ident.org_nr);

      with src as materialized (
        select r, i.je_id, nextval('public.afr_je_history_history_id_seq') as hid, afr_sni_snapshot(r->'sni') as snap
        from jsonb_array_elements(p_records) r join afr_je_ident i on i.pe_org_nr = r->>'key'
      ), h as (
        insert into afr_je_history (history_id, je_id, kommun_sate, lan_sate, ae_ant, anst_kl, ftg_stat, jurform, start_dat, slut_dat,
          reg_dat, oms_ar, oms_kl, ag_kat, arb_giv_stat, moms_stat, f_skatt_stat, bol_stat, priv_publ, sektor,
          row_hash, change_types, valid_from, sync_id, sni)
        overriding system value
        select hid, je_id, r->>'kommun_sate', r->>'lan_sate', (r->>'ae_ant')::int, r->>'anst_kl', r->>'ftg_stat', r->>'jurform',
          (r->>'start_dat')::date, (r->>'slut_dat')::date, (r->>'reg_dat')::date, (r->>'oms_ar')::int, r->>'oms_kl',
          r->>'ag_kat', r->>'arb_giv_stat', r->>'moms_stat', r->>'f_skatt_stat', r->>'bol_stat', r->>'priv_publ', r->>'sektor',
          r->>'hash', array['ny'], v_sync.fetched_at, p_sync_id, snap
        from src
      ), c as (
        insert into afr_je_current (je_id, kommun_sate, lan_sate, ae_ant, anst_kl, ftg_stat, jurform, start_dat, slut_dat,
          reg_dat, oms_ar, oms_kl, ag_kat, arb_giv_stat, moms_stat, f_skatt_stat, bol_stat, priv_publ, sektor,
          row_hash, first_seen_at, current_history_id, sync_id, primary_sni)
        select je_id, r->>'kommun_sate', r->>'lan_sate', (r->>'ae_ant')::int, r->>'anst_kl', r->>'ftg_stat', r->>'jurform',
          (r->>'start_dat')::date, (r->>'slut_dat')::date, (r->>'reg_dat')::date, (r->>'oms_ar')::int, r->>'oms_kl',
          r->>'ag_kat', r->>'arb_giv_stat', r->>'moms_stat', r->>'f_skatt_stat', r->>'bol_stat', r->>'priv_publ', r->>'sektor',
          r->>'hash', v_sync.fetched_at, hid, p_sync_id, afr_sni_primary(snap)
        from src
      )
      insert into afr_je_sni_current (je_id, rangordning, naringsgren, andel_procent, avdelnings_kod)
      select src.je_id, (e->>'r')::int, e->>'kod', (e->>'andel')::int, e->>'avd'
      from src cross join lateral jsonb_array_elements(src.snap) e;
    else
      insert into afr_je_ident (pe_org_nr)
      select distinct r->>'pe_org_nr' from jsonb_array_elements(p_records) r where r->>'pe_org_nr' is not null
      on conflict (pe_org_nr) do nothing;

      with src as materialized (
        select r, (r->>'key')::bigint as cfar_nr, i.je_id, nextval('public.afr_ae_history_history_id_seq') as hid,
          afr_sni_snapshot(r->'sni') as snap
        from jsonb_array_elements(p_records) r left join afr_je_ident i on i.pe_org_nr = r->>'pe_org_nr'
      ), h as (
        insert into afr_ae_history (history_id, cfar_nr, je_id, ae_stat, anst_kl, hj_verks_je, ae_typ, start_dat, slut_dat, lan, kommun,
          nord_sw, ost_sw, tat_sma_typ_kod, tat_ort_sma_ort_kod, tat_ort_sma_ort_ben, row_hash, change_types, valid_from, sync_id, sni)
        overriding system value
        select hid, cfar_nr, je_id, (r->>'ae_stat')::int, (r->>'anst_kl')::int, (r->>'hj_verks_je')::int, (r->>'ae_typ')::int,
          (r->>'start_dat')::date, (r->>'slut_dat')::date, r->>'lan', r->>'kommun', (r->>'nord_sw')::int, (r->>'ost_sw')::int,
          r->>'tat_sma_typ_kod', r->>'tat_ort_sma_ort_kod', r->>'tat_ort_sma_ort_ben', r->>'hash', array['ny'], v_sync.fetched_at, p_sync_id, snap
        from src
      ), c as (
        insert into afr_ae_current (cfar_nr, je_id, ae_stat, anst_kl, hj_verks_je, ae_typ, start_dat, slut_dat, lan, kommun,
          nord_sw, ost_sw, tat_sma_typ_kod, tat_ort_sma_ort_kod, tat_ort_sma_ort_ben, row_hash, first_seen_at, current_history_id, sync_id, primary_sni)
        select cfar_nr, je_id, (r->>'ae_stat')::int, (r->>'anst_kl')::int, (r->>'hj_verks_je')::int, (r->>'ae_typ')::int,
          (r->>'start_dat')::date, (r->>'slut_dat')::date, r->>'lan', r->>'kommun', (r->>'nord_sw')::int, (r->>'ost_sw')::int,
          r->>'tat_sma_typ_kod', r->>'tat_ort_sma_ort_kod', r->>'tat_ort_sma_ort_ben', r->>'hash', v_sync.fetched_at, hid, p_sync_id,
          afr_sni_primary(snap)
        from src
      )
      insert into afr_ae_sni_current (cfar_nr, rangordning, naringsgren, andel_procent, avdelnings_kod)
      select src.cfar_nr, (e->>'r')::int, e->>'kod', (e->>'andel')::int, e->>'avd'
      from src cross join lateral jsonb_array_elements(src.snap) e;
    end if;
  else
    insert into afr_stage_records (sync_id, entity, key, op, payload, row_hash)
    select p_sync_id, p_entity, r->>'key', 'upsert', r, r->>'hash' from jsonb_array_elements(p_records) r;
    insert into afr_stage_records (sync_id, entity, key, op)
    select p_sync_id, p_entity, k, 'remove' from jsonb_array_elements_text(p_removed) k;
  end if;

  insert into afr_sync_chunks (sync_id, entity, chunk_index, checksum, row_count, removed_count)
  values (p_sync_id, p_entity, p_chunk_index, p_checksum, v_rows, v_removed);

  update afr_syncs set
    received_je_chunks = received_je_chunks + (p_entity = 'je')::int,
    received_ae_chunks = received_ae_chunks + (p_entity = 'ae')::int,
    last_activity_at = now()
  where id = p_sync_id;

  return jsonb_build_object('duplicate', false, 'chunk_index', p_chunk_index, 'entity', p_entity, 'rows', v_rows, 'removed', v_removed);
end $function$;

-- Stegvis ifyllnad av primary_sni för JE som lästs in före hybridmodellen (sidintervall i tabellen).
create or replace function public.afr_backfill_primary_sni(p_from_page integer, p_pages integer default 1000)
returns jsonb language plpgsql security definer set search_path = public set statement_timeout = '280s' as $$
declare v_n integer; v_total integer;
begin
  if p_pages < 1 or p_pages > 5000 then raise exception 'p_pages 1..5000' using errcode = 'invalid_parameter_value'; end if;
  update afr_je_current c set primary_sni = s.kod
  from (select je_id, min(naringsgren collate "C") kod from afr_je_sni_current where rangordning = 1 group by je_id) s
  where c.ctid >= format('(%s,0)', p_from_page)::tid and c.ctid < format('(%s,0)', p_from_page + p_pages)::tid
    and c.primary_sni is null and s.je_id = c.je_id;
  get diagnostics v_n = row_count;
  v_total := (pg_relation_size('public.afr_je_current') / 8192)::int;
  return jsonb_build_object('updated', v_n, 'next_page', p_from_page + p_pages, 'total_pages', v_total,
    'done', p_from_page + p_pages >= v_total);
end $$;
revoke all on function public.afr_backfill_primary_sni(integer, integer) from public, anon, authenticated;
grant execute on function public.afr_backfill_primary_sni(integer, integer) to service_role;