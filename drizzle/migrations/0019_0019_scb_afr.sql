-- SCB Allmänna företagsregistret (AFR): rikstäckande JE/AE med egen historik.
-- Skrivning sker endast via security definer-funktioner som bara service_role (ETL-endpoints) får anropa.

create table public.afr_syncs (
  id uuid primary key default gen_random_uuid(),
  mode text not null check (mode in ('initial','daily')),
  status text not null default 'receiving' check (status in ('receiving','succeeded','failed')),
  run_id uuid references public.data_source_runs(id),
  source_date text not null,
  api_version text,
  fetched_at timestamptz not null,
  je_source_count integer not null check (je_source_count >= 0),
  ae_source_count integer not null check (ae_source_count >= 0),
  expected_je_chunks integer not null check (expected_je_chunks between 0 and 2000),
  expected_ae_chunks integer not null check (expected_ae_chunks between 0 and 2000),
  received_je_chunks integer not null default 0,
  received_ae_chunks integer not null default 0,
  confirm_large_removal boolean not null default false,
  stats jsonb not null default '{}'::jsonb,
  error_message text,
  created_at timestamptz not null default now(),
  last_activity_at timestamptz not null default now(),
  finalized_at timestamptz
);
create index afr_syncs_status_idx on public.afr_syncs(mode, status, created_at desc);

create table public.afr_sync_chunks (
  sync_id uuid not null references public.afr_syncs(id) on delete cascade,
  entity text not null check (entity in ('je','ae')),
  chunk_index integer not null,
  checksum text not null,
  row_count integer not null,
  removed_count integer not null default 0,
  created_at timestamptz not null default now(),
  primary key (sync_id, entity, chunk_index)
);

create table public.afr_stage_records (
  sync_id uuid not null references public.afr_syncs(id) on delete cascade,
  entity text not null check (entity in ('je','ae')),
  key text not null,
  op text not null check (op in ('upsert','remove')),
  payload jsonb,
  row_hash text,
  primary key (sync_id, entity, key)
);

-- Skyddade identifierare (JE kan vara fysiska personer). Läses bara av admin/ETL.
create table public.afr_je_ident (
  je_id uuid primary key default gen_random_uuid(),
  pe_org_nr text not null unique,
  org_nr text,
  first_seen_at timestamptz not null default now()
);

create table public.afr_je_current (
  je_id uuid primary key references public.afr_je_ident(je_id),
  kommun_sate text, lan_sate text, ae_ant integer, anst_kl text, ftg_stat text, jurform text,
  start_dat date, slut_dat date, reg_dat date, oms_ar integer, oms_kl text, ag_kat text,
  arb_giv_stat text, moms_stat text, f_skatt_stat text, bol_stat text, priv_publ text, sektor text,
  row_hash text not null,
  in_source boolean not null default true,
  first_seen_at timestamptz not null default now(),
  removed_observed_at timestamptz,
  current_history_id bigint,
  sync_id uuid not null references public.afr_syncs(id)
);
create index afr_je_current_lan_idx on public.afr_je_current(lan_sate);
create index afr_je_current_kommun_idx on public.afr_je_current(kommun_sate);
create index afr_je_current_agkat_idx on public.afr_je_current(ag_kat);
create index afr_je_current_sync_idx on public.afr_je_current(sync_id);

create table public.afr_je_history (
  history_id bigint generated always as identity primary key,
  je_id uuid not null references public.afr_je_ident(je_id),
  kommun_sate text, lan_sate text, ae_ant integer, anst_kl text, ftg_stat text, jurform text,
  start_dat date, slut_dat date, reg_dat date, oms_ar integer, oms_kl text, ag_kat text,
  arb_giv_stat text, moms_stat text, f_skatt_stat text, bol_stat text, priv_publ text, sektor text,
  row_hash text not null,
  change_types text[] not null,
  in_source boolean not null default true,
  valid_from timestamptz not null,
  valid_to timestamptz,
  sync_id uuid not null references public.afr_syncs(id)
);
create index afr_je_history_je_idx on public.afr_je_history(je_id, valid_from);
create index afr_je_history_sync_idx on public.afr_je_history(sync_id);

create table public.afr_je_sni_current (
  je_id uuid not null references public.afr_je_current(je_id) on delete cascade,
  rangordning integer not null,
  naringsgren text not null,
  andel_procent integer,
  avdelnings_kod text,
  primary key (je_id, rangordning, naringsgren)
);
create index afr_je_sni_current_kod_idx on public.afr_je_sni_current(naringsgren, rangordning);

create table public.afr_je_sni_history (
  history_id bigint not null references public.afr_je_history(history_id) on delete cascade,
  rangordning integer not null,
  naringsgren text not null,
  andel_procent integer,
  avdelnings_kod text,
  primary key (history_id, rangordning, naringsgren)
);

create table public.afr_ae_current (
  cfar_nr bigint primary key,
  je_id uuid references public.afr_je_ident(je_id),
  ae_stat integer, anst_kl integer, hj_verks_je integer, ae_typ integer,
  start_dat date, slut_dat date, lan text, kommun text, nord_sw integer, ost_sw integer,
  tat_sma_typ_kod text, tat_ort_sma_ort_kod text, tat_ort_sma_ort_ben text,
  row_hash text not null,
  in_source boolean not null default true,
  first_seen_at timestamptz not null default now(),
  removed_observed_at timestamptz,
  current_history_id bigint,
  sync_id uuid not null references public.afr_syncs(id)
);
create index afr_ae_current_lan_idx on public.afr_ae_current(lan);
create index afr_ae_current_kommun_idx on public.afr_ae_current(kommun);
create index afr_ae_current_anstkl_idx on public.afr_ae_current(anst_kl);
create index afr_ae_current_je_idx on public.afr_ae_current(je_id);
create index afr_ae_current_sync_idx on public.afr_ae_current(sync_id);

create table public.afr_ae_history (
  history_id bigint generated always as identity primary key,
  cfar_nr bigint not null,
  je_id uuid references public.afr_je_ident(je_id),
  ae_stat integer, anst_kl integer, hj_verks_je integer, ae_typ integer,
  start_dat date, slut_dat date, lan text, kommun text, nord_sw integer, ost_sw integer,
  tat_sma_typ_kod text, tat_ort_sma_ort_kod text, tat_ort_sma_ort_ben text,
  row_hash text not null,
  change_types text[] not null,
  in_source boolean not null default true,
  valid_from timestamptz not null,
  valid_to timestamptz,
  sync_id uuid not null references public.afr_syncs(id)
);
create index afr_ae_history_cfar_idx on public.afr_ae_history(cfar_nr, valid_from);
create index afr_ae_history_sync_idx on public.afr_ae_history(sync_id);

create table public.afr_ae_sni_current (
  cfar_nr bigint not null references public.afr_ae_current(cfar_nr) on delete cascade,
  rangordning integer not null,
  naringsgren text not null,
  andel_procent integer,
  avdelnings_kod text,
  primary key (cfar_nr, rangordning, naringsgren)
);
create index afr_ae_sni_current_kod_idx on public.afr_ae_sni_current(naringsgren, rangordning);

create table public.afr_ae_sni_history (
  history_id bigint not null references public.afr_ae_history(history_id) on delete cascade,
  rangordning integer not null,
  naringsgren text not null,
  andel_procent integer,
  avdelnings_kod text,
  primary key (history_id, rangordning, naringsgren)
);

create table public.afr_code_values (
  table_name text not null,
  kod text not null,
  klartext text,
  extra jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  first_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (table_name, kod)
);

create table public.afr_code_value_history (
  id bigint generated always as identity primary key,
  table_name text not null,
  kod text not null,
  change text not null check (change in ('added','changed','removed','reactivated')),
  old_klartext text, new_klartext text, old_extra jsonb, new_extra jsonb,
  observed_at timestamptz not null default now()
);

-- Gruppering av agKat till Offentlig / Privat svensk / Privat utländsk.
-- Fylls efter granskning av SCB:s kodtabell; originalkoden finns alltid kvar.
create table public.afr_agkat_group (
  ag_kat text primary key,
  grupp text not null check (grupp in ('Offentlig','Privat – svensk kontroll','Privat – utländsk kontroll'))
);

-- Grants
grant all on public.afr_syncs, public.afr_sync_chunks, public.afr_stage_records, public.afr_je_ident,
  public.afr_je_current, public.afr_je_history, public.afr_je_sni_current, public.afr_je_sni_history,
  public.afr_ae_current, public.afr_ae_history, public.afr_ae_sni_current, public.afr_ae_sni_history,
  public.afr_code_values, public.afr_code_value_history, public.afr_agkat_group to service_role;
grant select on public.afr_syncs, public.afr_je_ident,
  public.afr_je_current, public.afr_je_history, public.afr_je_sni_current, public.afr_je_sni_history,
  public.afr_ae_current, public.afr_ae_history, public.afr_ae_sni_current, public.afr_ae_sni_history,
  public.afr_code_values, public.afr_code_value_history, public.afr_agkat_group to authenticated;

alter table public.afr_syncs enable row level security;
alter table public.afr_sync_chunks enable row level security;
alter table public.afr_stage_records enable row level security;
alter table public.afr_je_ident enable row level security;
alter table public.afr_je_current enable row level security;
alter table public.afr_je_history enable row level security;
alter table public.afr_je_sni_current enable row level security;
alter table public.afr_je_sni_history enable row level security;
alter table public.afr_ae_current enable row level security;
alter table public.afr_ae_history enable row level security;
alter table public.afr_ae_sni_current enable row level security;
alter table public.afr_ae_sni_history enable row level security;
alter table public.afr_code_values enable row level security;
alter table public.afr_code_value_history enable row level security;
alter table public.afr_agkat_group enable row level security;

create policy "AFR synkar för admin" on public.afr_syncs for select to authenticated using (public.has_role(auth.uid(), 'admin'));
create policy "AFR identiteter för admin" on public.afr_je_ident for select to authenticated using (public.has_role(auth.uid(), 'admin'));
create policy "AFR JE för admin" on public.afr_je_current for select to authenticated using (public.has_role(auth.uid(), 'admin'));
create policy "AFR JE-historik för admin" on public.afr_je_history for select to authenticated using (public.has_role(auth.uid(), 'admin'));
create policy "AFR JE-SNI för admin" on public.afr_je_sni_current for select to authenticated using (public.has_role(auth.uid(), 'admin'));
create policy "AFR JE-SNI-historik för admin" on public.afr_je_sni_history for select to authenticated using (public.has_role(auth.uid(), 'admin'));
create policy "AFR AE för admin" on public.afr_ae_current for select to authenticated using (public.has_role(auth.uid(), 'admin'));
create policy "AFR AE-historik för admin" on public.afr_ae_history for select to authenticated using (public.has_role(auth.uid(), 'admin'));
create policy "AFR AE-SNI för admin" on public.afr_ae_sni_current for select to authenticated using (public.has_role(auth.uid(), 'admin'));
create policy "AFR AE-SNI-historik för admin" on public.afr_ae_sni_history for select to authenticated using (public.has_role(auth.uid(), 'admin'));
create policy "AFR kodtabeller för admin" on public.afr_code_values for select to authenticated using (public.has_role(auth.uid(), 'admin'));
create policy "AFR kodhistorik för admin" on public.afr_code_value_history for select to authenticated using (public.has_role(auth.uid(), 'admin'));
create policy "AFR agKat-grupper för admin" on public.afr_agkat_group for select to authenticated using (public.has_role(auth.uid(), 'admin'));

-- Deterministisk kanonisk form + hash. Måste vara identisk med R/etl/afr_normalize.R.
create or replace function public.afr_canonical_sni(p jsonb)
returns text language sql immutable set search_path = public as $$
  select coalesce(string_agg(
    coalesce(e->>'r','') || ':' || coalesce(e->>'kod','') || ':' || coalesce(e->>'andel',''),
    ';' order by (e->>'r')::int, (e->>'kod') collate "C"), '')
  from jsonb_array_elements(case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end) e
$$;

create or replace function public.afr_je_canonical(p jsonb)
returns text language sql immutable set search_path = public as $$
  select 'je1|' || coalesce(p->>'kommun_sate','') || '|' || coalesce(p->>'lan_sate','') || '|' ||
    coalesce(p->>'ae_ant','') || '|' || coalesce(p->>'anst_kl','') || '|' || coalesce(p->>'ftg_stat','') || '|' ||
    coalesce(p->>'jurform','') || '|' || coalesce(p->>'start_dat','') || '|' || coalesce(p->>'slut_dat','') || '|' ||
    coalesce(p->>'reg_dat','') || '|' || coalesce(p->>'oms_ar','') || '|' || coalesce(p->>'oms_kl','') || '|' ||
    coalesce(p->>'ag_kat','') || '|' || coalesce(p->>'arb_giv_stat','') || '|' || coalesce(p->>'moms_stat','') || '|' ||
    coalesce(p->>'f_skatt_stat','') || '|' || coalesce(p->>'bol_stat','') || '|' || coalesce(p->>'priv_publ','') || '|' ||
    coalesce(p->>'sektor','') || '|' || public.afr_canonical_sni(p->'sni')
$$;

create or replace function public.afr_ae_canonical(p jsonb)
returns text language sql immutable set search_path = public as $$
  select 'ae1|' || coalesce(p->>'pe_org_nr','') || '|' || coalesce(p->>'ae_stat','') || '|' ||
    coalesce(p->>'anst_kl','') || '|' || coalesce(p->>'hj_verks_je','') || '|' || coalesce(p->>'ae_typ','') || '|' ||
    coalesce(p->>'start_dat','') || '|' || coalesce(p->>'slut_dat','') || '|' || coalesce(p->>'lan','') || '|' ||
    coalesce(p->>'kommun','') || '|' || coalesce(p->>'nord_sw','') || '|' || coalesce(p->>'ost_sw','') || '|' ||
    coalesce(p->>'tat_sma_typ_kod','') || '|' || coalesce(p->>'tat_ort_sma_ort_kod','') || '|' ||
    coalesce(p->>'tat_ort_sma_ort_ben','') || '|' || public.afr_canonical_sni(p->'sni')
$$;

create or replace function public.afr_hash(p_text text)
returns text language sql immutable set search_path = public as $$
  select encode(sha256(convert_to(p_text, 'UTF8')), 'hex')
$$;

-- Start av synk
create or replace function public.afr_start_sync(
  p_mode text, p_source_date text, p_api_version text, p_fetched_at timestamptz,
  p_je_source_count integer, p_ae_source_count integer,
  p_expected_je_chunks integer, p_expected_ae_chunks integer,
  p_confirm_large_removal boolean default false, p_details jsonb default '{}'::jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_run uuid;
begin
  perform pg_advisory_xact_lock(hashtext('scb-afr'));
  if p_mode not in ('initial','daily') then
    raise exception 'Okänt läge %', p_mode using errcode = 'invalid_parameter_value';
  end if;
  if exists (select 1 from afr_syncs where status = 'receiving') then
    raise exception 'En AFR-synk pågår redan' using errcode = 'invalid_parameter_value';
  end if;
  if p_mode = 'initial' and exists (select 1 from afr_syncs where status = 'succeeded') then
    raise exception 'Första laddningen är redan publicerad; använd daglig synk' using errcode = 'invalid_parameter_value';
  end if;
  if p_mode = 'initial' and (exists (select 1 from afr_je_current) or exists (select 1 from afr_ae_current)) then
    raise exception 'Rester från en misslyckad första laddning finns; städa först' using errcode = 'invalid_parameter_value';
  end if;
  if p_mode = 'daily' and not exists (select 1 from afr_syncs where mode = 'initial' and status = 'succeeded') then
    raise exception 'Första laddningen saknas' using errcode = 'no_data_found';
  end if;

  insert into data_source_runs (source, source_id, status, source_period, details)
  values ('scb-afr', 'scb-afr', 'started', p_source_date,
          coalesce(p_details, '{}'::jsonb) || jsonb_build_object('mode', p_mode, 'je_source_count', p_je_source_count,
            'ae_source_count', p_ae_source_count, 'api_version', p_api_version))
  returning id into v_run;

  insert into afr_syncs (mode, run_id, source_date, api_version, fetched_at, je_source_count, ae_source_count,
    expected_je_chunks, expected_ae_chunks, confirm_large_removal, stats)
  values (p_mode, v_run, p_source_date, p_api_version, p_fetched_at, p_je_source_count, p_ae_source_count,
    p_expected_je_chunks, p_expected_ae_chunks, coalesce(p_confirm_large_removal, false), coalesce(p_details, '{}'::jsonb))
  returning id into v_id;
  return v_id;
end $$;

-- Chunk: verifierar hash per post. Första laddningen skriver direkt (osynligt tills finalisering),
-- daglig synk skriver till staging.
create or replace function public.afr_store_chunk(
  p_sync_id uuid, p_entity text, p_chunk_index integer, p_records jsonb, p_removed jsonb, p_checksum text
) returns jsonb language plpgsql security definer set search_path = public set statement_timeout = '60s' as $$
declare
  v_sync afr_syncs%rowtype; v_existing afr_sync_chunks%rowtype;
  v_expected integer; v_rows integer; v_removed integer; v_bad text;
begin
  select * into v_sync from afr_syncs where id = p_sync_id for update;
  if not found then raise exception 'Synk % finns inte', p_sync_id using errcode = 'no_data_found'; end if;
  if v_sync.status <> 'receiving' then
    raise exception 'Synk har status %', v_sync.status using errcode = 'invalid_parameter_value';
  end if;
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

  -- Hashverifiering: R och databasen måste ge identisk hash.
  if p_entity = 'je' then
    select r->>'key' into v_bad from jsonb_array_elements(p_records) r
    where r->>'key' is null or r->>'hash' is distinct from afr_hash(afr_je_canonical(r)) limit 1;
  else
    select coalesce(r->>'key','(saknas)') into v_bad from jsonb_array_elements(p_records) r
    where r->>'key' is null or (r->>'key') !~ '^[0-9]+$' or r->>'hash' is distinct from afr_hash(afr_ae_canonical(r)) limit 1;
  end if;
  if v_bad is not null then
    raise exception 'Hash eller nyckel stämmer inte för post %', v_bad using errcode = 'invalid_parameter_value';
  end if;

  if v_sync.mode = 'initial' then
    if v_removed > 0 then raise exception 'Första laddningen kan inte ha bortfall' using errcode = 'invalid_parameter_value'; end if;

    if p_entity = 'je' then
      insert into afr_je_ident (pe_org_nr, org_nr)
      select r->>'key', nullif(r->>'org_nr','') from jsonb_array_elements(p_records) r
      on conflict (pe_org_nr) do update set org_nr = coalesce(excluded.org_nr, afr_je_ident.org_nr);

      create temp table _afr_h on commit drop as
      with src as (
        select r, i.je_id from jsonb_array_elements(p_records) r join afr_je_ident i on i.pe_org_nr = r->>'key'
      ), ins as (
        insert into afr_je_history (je_id, kommun_sate, lan_sate, ae_ant, anst_kl, ftg_stat, jurform, start_dat, slut_dat,
          reg_dat, oms_ar, oms_kl, ag_kat, arb_giv_stat, moms_stat, f_skatt_stat, bol_stat, priv_publ, sektor,
          row_hash, change_types, valid_from, sync_id)
        select je_id, r->>'kommun_sate', r->>'lan_sate', (r->>'ae_ant')::int, r->>'anst_kl', r->>'ftg_stat', r->>'jurform',
          (r->>'start_dat')::date, (r->>'slut_dat')::date, (r->>'reg_dat')::date, (r->>'oms_ar')::int, r->>'oms_kl',
          r->>'ag_kat', r->>'arb_giv_stat', r->>'moms_stat', r->>'f_skatt_stat', r->>'bol_stat', r->>'priv_publ', r->>'sektor',
          r->>'hash', array['ny'], v_sync.fetched_at, p_sync_id
        from src returning history_id, je_id
      ) select ins.history_id, ins.je_id, src.r from ins join src on src.je_id = ins.je_id;

      insert into afr_je_current (je_id, kommun_sate, lan_sate, ae_ant, anst_kl, ftg_stat, jurform, start_dat, slut_dat,
        reg_dat, oms_ar, oms_kl, ag_kat, arb_giv_stat, moms_stat, f_skatt_stat, bol_stat, priv_publ, sektor,
        row_hash, first_seen_at, current_history_id, sync_id)
      select je_id, r->>'kommun_sate', r->>'lan_sate', (r->>'ae_ant')::int, r->>'anst_kl', r->>'ftg_stat', r->>'jurform',
        (r->>'start_dat')::date, (r->>'slut_dat')::date, (r->>'reg_dat')::date, (r->>'oms_ar')::int, r->>'oms_kl',
        r->>'ag_kat', r->>'arb_giv_stat', r->>'moms_stat', r->>'f_skatt_stat', r->>'bol_stat', r->>'priv_publ', r->>'sektor',
        r->>'hash', v_sync.fetched_at, history_id, p_sync_id
      from _afr_h;

      insert into afr_je_sni_current (je_id, rangordning, naringsgren, andel_procent, avdelnings_kod)
      select h.je_id, (e->>'r')::int, e->>'kod', (e->>'andel')::int, e->>'avd'
      from _afr_h h, jsonb_array_elements(coalesce(h.r->'sni','[]'::jsonb)) e;
      insert into afr_je_sni_history (history_id, rangordning, naringsgren, andel_procent, avdelnings_kod)
      select h.history_id, (e->>'r')::int, e->>'kod', (e->>'andel')::int, e->>'avd'
      from _afr_h h, jsonb_array_elements(coalesce(h.r->'sni','[]'::jsonb)) e;
    else
      insert into afr_je_ident (pe_org_nr)
      select distinct r->>'pe_org_nr' from jsonb_array_elements(p_records) r where r->>'pe_org_nr' is not null
      on conflict (pe_org_nr) do nothing;

      create temp table _afr_h on commit drop as
      with src as (
        select r, (r->>'key')::bigint as cfar_nr, i.je_id
        from jsonb_array_elements(p_records) r left join afr_je_ident i on i.pe_org_nr = r->>'pe_org_nr'
      ), ins as (
        insert into afr_ae_history (cfar_nr, je_id, ae_stat, anst_kl, hj_verks_je, ae_typ, start_dat, slut_dat, lan, kommun,
          nord_sw, ost_sw, tat_sma_typ_kod, tat_ort_sma_ort_kod, tat_ort_sma_ort_ben, row_hash, change_types, valid_from, sync_id)
        select cfar_nr, je_id, (r->>'ae_stat')::int, (r->>'anst_kl')::int, (r->>'hj_verks_je')::int, (r->>'ae_typ')::int,
          (r->>'start_dat')::date, (r->>'slut_dat')::date, r->>'lan', r->>'kommun', (r->>'nord_sw')::int, (r->>'ost_sw')::int,
          r->>'tat_sma_typ_kod', r->>'tat_ort_sma_ort_kod', r->>'tat_ort_sma_ort_ben', r->>'hash', array['ny'], v_sync.fetched_at, p_sync_id
        from src returning history_id, cfar_nr
      ) select ins.history_id, src.cfar_nr, src.je_id, src.r from ins join src on src.cfar_nr = ins.cfar_nr;

      insert into afr_ae_current (cfar_nr, je_id, ae_stat, anst_kl, hj_verks_je, ae_typ, start_dat, slut_dat, lan, kommun,
        nord_sw, ost_sw, tat_sma_typ_kod, tat_ort_sma_ort_kod, tat_ort_sma_ort_ben, row_hash, first_seen_at, current_history_id, sync_id)
      select cfar_nr, je_id, (r->>'ae_stat')::int, (r->>'anst_kl')::int, (r->>'hj_verks_je')::int, (r->>'ae_typ')::int,
        (r->>'start_dat')::date, (r->>'slut_dat')::date, r->>'lan', r->>'kommun', (r->>'nord_sw')::int, (r->>'ost_sw')::int,
        r->>'tat_sma_typ_kod', r->>'tat_ort_sma_ort_kod', r->>'tat_ort_sma_ort_ben', r->>'hash', v_sync.fetched_at, history_id, p_sync_id
      from _afr_h;

      insert into afr_ae_sni_current (cfar_nr, rangordning, naringsgren, andel_procent, avdelnings_kod)
      select h.cfar_nr, (e->>'r')::int, e->>'kod', (e->>'andel')::int, e->>'avd'
      from _afr_h h, jsonb_array_elements(coalesce(h.r->'sni','[]'::jsonb)) e;
      insert into afr_ae_sni_history (history_id, rangordning, naringsgren, andel_procent, avdelnings_kod)
      select h.history_id, (e->>'r')::int, e->>'kod', (e->>'andel')::int, e->>'avd'
      from _afr_h h, jsonb_array_elements(coalesce(h.r->'sni','[]'::jsonb)) e;
    end if;
  else
    insert into afr_stage_records (sync_id, entity, key, op, payload, row_hash)
    select p_sync_id, p_entity, r->>'key', 'upsert', r, r->>'hash' from jsonb_array_elements(p_records) r;
    insert into afr_stage_records (sync_id, entity, key, op)
    select p_sync_id, p_entity, k from jsonb_array_elements_text(p_removed) k;
  end if;

  insert into afr_sync_chunks (sync_id, entity, chunk_index, checksum, row_count, removed_count)
  values (p_sync_id, p_entity, p_chunk_index, p_checksum, v_rows, v_removed);

  update afr_syncs set
    received_je_chunks = received_je_chunks + (p_entity = 'je')::int,
    received_ae_chunks = received_ae_chunks + (p_entity = 'ae')::int,
    last_activity_at = now()
  where id = p_sync_id;

  return jsonb_build_object('duplicate', false, 'chunk_index', p_chunk_index, 'entity', p_entity,
    'rows', v_rows, 'removed', v_removed);
end $$;

-- Finalisering
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

    -- JE: förbered
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

    -- Balanskontroll: tidigare + nya − bortfallna = källans antal
    if v_je_prev + v_je_new - v_je_rm <> v_sync.je_source_count then
      raise exception 'JE-balans stämmer inte: % + % − % ≠ %', v_je_prev, v_je_new, v_je_rm, v_sync.je_source_count using errcode = 'invalid_parameter_value';
    end if;
    if v_ae_prev + v_ae_new - v_ae_rm <> v_sync.ae_source_count then
      raise exception 'AE-balans stämmer inte: % + % − % ≠ %', v_ae_prev, v_ae_new, v_ae_rm, v_sync.ae_source_count using errcode = 'invalid_parameter_value';
    end if;
    -- Säkerhetströskel för stora bortfall
    if not v_sync.confirm_large_removal and
       (v_je_rm > greatest(1000, v_je_prev * 0.02) or v_ae_rm > greatest(1000, v_ae_prev * 0.02)) then
      raise exception 'Ovanligt stort bortfall (JE %, AE %) – kräver manuell kontroll', v_je_rm, v_ae_rm using errcode = 'invalid_parameter_value';
    end if;

    -- JE: tillämpa nya/ändrade
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
        row_hash, change_types, valid_from, sync_id)
      select u.je_id, p->>'kommun_sate', p->>'lan_sate', (p->>'ae_ant')::int, p->>'anst_kl', p->>'ftg_stat', p->>'jurform',
        (p->>'start_dat')::date, (p->>'slut_dat')::date, (p->>'reg_dat')::date, (p->>'oms_ar')::int, p->>'oms_kl',
        p->>'ag_kat', p->>'arb_giv_stat', p->>'moms_stat', p->>'f_skatt_stat', p->>'bol_stat', p->>'priv_publ', p->>'sektor',
        u.row_hash, coalesce(t.change_types, array[]::text[]), v_now, p_sync_id
      from _je_up u join _je_types t on t.je_id = u.je_id
      returning history_id, je_id
    ) select ins.history_id, u.je_id, u.p, u.row_hash from ins join _je_up u on u.je_id = ins.je_id;

    insert into afr_je_current as c (je_id, kommun_sate, lan_sate, ae_ant, anst_kl, ftg_stat, jurform, start_dat, slut_dat,
      reg_dat, oms_ar, oms_kl, ag_kat, arb_giv_stat, moms_stat, f_skatt_stat, bol_stat, priv_publ, sektor,
      row_hash, in_source, first_seen_at, removed_observed_at, current_history_id, sync_id)
    select je_id, p->>'kommun_sate', p->>'lan_sate', (p->>'ae_ant')::int, p->>'anst_kl', p->>'ftg_stat', p->>'jurform',
      (p->>'start_dat')::date, (p->>'slut_dat')::date, (p->>'reg_dat')::date, (p->>'oms_ar')::int, p->>'oms_kl',
      p->>'ag_kat', p->>'arb_giv_stat', p->>'moms_stat', p->>'f_skatt_stat', p->>'bol_stat', p->>'priv_publ', p->>'sektor',
      row_hash, true, v_now, null, history_id, p_sync_id
    from _je_h
    on conflict (je_id) do update set kommun_sate = excluded.kommun_sate, lan_sate = excluded.lan_sate, ae_ant = excluded.ae_ant,
      anst_kl = excluded.anst_kl, ftg_stat = excluded.ftg_stat, jurform = excluded.jurform, start_dat = excluded.start_dat,
      slut_dat = excluded.slut_dat, reg_dat = excluded.reg_dat, oms_ar = excluded.oms_ar, oms_kl = excluded.oms_kl,
      ag_kat = excluded.ag_kat, arb_giv_stat = excluded.arb_giv_stat, moms_stat = excluded.moms_stat,
      f_skatt_stat = excluded.f_skatt_stat, bol_stat = excluded.bol_stat, priv_publ = excluded.priv_publ, sektor = excluded.sektor,
      row_hash = excluded.row_hash, in_source = true, removed_observed_at = null,
      current_history_id = excluded.current_history_id, sync_id = excluded.sync_id;

    delete from afr_je_sni_current where je_id in (select je_id from _je_h);
    insert into afr_je_sni_current (je_id, rangordning, naringsgren, andel_procent, avdelnings_kod)
      select h.je_id, (e->>'r')::int, e->>'kod', (e->>'andel')::int, e->>'avd' from _je_h h, jsonb_array_elements(coalesce(h.p->'sni','[]'::jsonb)) e;
    insert into afr_je_sni_history (history_id, rangordning, naringsgren, andel_procent, avdelnings_kod)
      select h.history_id, (e->>'r')::int, e->>'kod', (e->>'andel')::int, e->>'avd' from _je_h h, jsonb_array_elements(coalesce(h.p->'sni','[]'::jsonb)) e;

    -- JE: bortfall (endast efter fullständig traversering, kontrollerat ovan)
    update afr_je_history h set valid_to = v_now from afr_je_current c
      where c.je_id in (select je_id from _je_rm) and h.history_id = c.current_history_id and h.valid_to is null;
    create temp table _je_rh on commit drop as
    with ins as (
      insert into afr_je_history (je_id, kommun_sate, lan_sate, ae_ant, anst_kl, ftg_stat, jurform, start_dat, slut_dat,
        reg_dat, oms_ar, oms_kl, ag_kat, arb_giv_stat, moms_stat, f_skatt_stat, bol_stat, priv_publ, sektor,
        row_hash, change_types, in_source, valid_from, sync_id)
      select c.je_id, c.kommun_sate, c.lan_sate, c.ae_ant, c.anst_kl, c.ftg_stat, c.jurform, c.start_dat, c.slut_dat,
        c.reg_dat, c.oms_ar, c.oms_kl, c.ag_kat, c.arb_giv_stat, c.moms_stat, c.f_skatt_stat, c.bol_stat, c.priv_publ, c.sektor,
        c.row_hash, array['ej_längre_observerad'], false, v_now, p_sync_id
      from afr_je_current c where c.je_id in (select je_id from _je_rm)
      returning history_id, je_id
    ) select * from ins;
    insert into afr_je_sni_history (history_id, rangordning, naringsgren, andel_procent, avdelnings_kod)
      select r.history_id, s.rangordning, s.naringsgren, s.andel_procent, s.avdelnings_kod
      from _je_rh r join afr_je_sni_current s on s.je_id = r.je_id;
    update afr_je_current c set in_source = false, removed_observed_at = v_now, current_history_id = r.history_id, sync_id = p_sync_id
      from _je_rh r where r.je_id = c.je_id;

    -- AE: tillämpa nya/ändrade
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
        nord_sw, ost_sw, tat_sma_typ_kod, tat_ort_sma_ort_kod, tat_ort_sma_ort_ben, row_hash, change_types, valid_from, sync_id)
      select x.cfar_nr, x.new_je_id, (p->>'ae_stat')::int, (p->>'anst_kl')::int, (p->>'hj_verks_je')::int, (p->>'ae_typ')::int,
        (p->>'start_dat')::date, (p->>'slut_dat')::date, p->>'lan', p->>'kommun', (p->>'nord_sw')::int, (p->>'ost_sw')::int,
        p->>'tat_sma_typ_kod', p->>'tat_ort_sma_ort_kod', p->>'tat_ort_sma_ort_ben', x.row_hash,
        coalesce(t.change_types, array[]::text[]), v_now, p_sync_id
      from _ae_x x join _ae_types t on t.cfar_nr = x.cfar_nr
      returning history_id, cfar_nr
    ) select ins.history_id, x.cfar_nr, x.new_je_id, x.p, x.row_hash from ins join _ae_x x on x.cfar_nr = ins.cfar_nr;

    insert into afr_ae_current as c (cfar_nr, je_id, ae_stat, anst_kl, hj_verks_je, ae_typ, start_dat, slut_dat, lan, kommun,
      nord_sw, ost_sw, tat_sma_typ_kod, tat_ort_sma_ort_kod, tat_ort_sma_ort_ben, row_hash, in_source, first_seen_at,
      removed_observed_at, current_history_id, sync_id)
    select cfar_nr, new_je_id, (p->>'ae_stat')::int, (p->>'anst_kl')::int, (p->>'hj_verks_je')::int, (p->>'ae_typ')::int,
      (p->>'start_dat')::date, (p->>'slut_dat')::date, p->>'lan', p->>'kommun', (p->>'nord_sw')::int, (p->>'ost_sw')::int,
      p->>'tat_sma_typ_kod', p->>'tat_ort_sma_ort_kod', p->>'tat_ort_sma_ort_ben', row_hash, true, v_now, null, history_id, p_sync_id
    from _ae_h
    on conflict (cfar_nr) do update set je_id = excluded.je_id, ae_stat = excluded.ae_stat, anst_kl = excluded.anst_kl,
      hj_verks_je = excluded.hj_verks_je, ae_typ = excluded.ae_typ, start_dat = excluded.start_dat, slut_dat = excluded.slut_dat,
      lan = excluded.lan, kommun = excluded.kommun, nord_sw = excluded.nord_sw, ost_sw = excluded.ost_sw,
      tat_sma_typ_kod = excluded.tat_sma_typ_kod, tat_ort_sma_ort_kod = excluded.tat_ort_sma_ort_kod,
      tat_ort_sma_ort_ben = excluded.tat_ort_sma_ort_ben, row_hash = excluded.row_hash, in_source = true,
      removed_observed_at = null, current_history_id = excluded.current_history_id, sync_id = excluded.sync_id;

    delete from afr_ae_sni_current where cfar_nr in (select cfar_nr from _ae_h);
    insert into afr_ae_sni_current (cfar_nr, rangordning, naringsgren, andel_procent, avdelnings_kod)
      select h.cfar_nr, (e->>'r')::int, e->>'kod', (e->>'andel')::int, e->>'avd' from _ae_h h, jsonb_array_elements(coalesce(h.p->'sni','[]'::jsonb)) e;
    insert into afr_ae_sni_history (history_id, rangordning, naringsgren, andel_procent, avdelnings_kod)
      select h.history_id, (e->>'r')::int, e->>'kod', (e->>'andel')::int, e->>'avd' from _ae_h h, jsonb_array_elements(coalesce(h.p->'sni','[]'::jsonb)) e;

    -- AE: bortfall
    update afr_ae_history h set valid_to = v_now from afr_ae_current c
      where c.cfar_nr in (select cfar_nr from _ae_rm) and h.history_id = c.current_history_id and h.valid_to is null;
    create temp table _ae_rh on commit drop as
    with ins as (
      insert into afr_ae_history (cfar_nr, je_id, ae_stat, anst_kl, hj_verks_je, ae_typ, start_dat, slut_dat, lan, kommun,
        nord_sw, ost_sw, tat_sma_typ_kod, tat_ort_sma_ort_kod, tat_ort_sma_ort_ben, row_hash, change_types, in_source, valid_from, sync_id)
      select c.cfar_nr, c.je_id, c.ae_stat, c.anst_kl, c.hj_verks_je, c.ae_typ, c.start_dat, c.slut_dat, c.lan, c.kommun,
        c.nord_sw, c.ost_sw, c.tat_sma_typ_kod, c.tat_ort_sma_ort_kod, c.tat_ort_sma_ort_ben, c.row_hash,
        array['ej_längre_observerad'], false, v_now, p_sync_id
      from afr_ae_current c where c.cfar_nr in (select cfar_nr from _ae_rm)
      returning history_id, cfar_nr
    ) select * from ins;
    insert into afr_ae_sni_history (history_id, rangordning, naringsgren, andel_procent, avdelnings_kod)
      select r.history_id, s.rangordning, s.naringsgren, s.andel_procent, s.avdelnings_kod
      from _ae_rh r join afr_ae_sni_current s on s.cfar_nr = r.cfar_nr;
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

create or replace function public.afr_abort_sync(p_sync_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_sync afr_syncs%rowtype;
begin
  select * into v_sync from afr_syncs where id = p_sync_id for update;
  if not found then raise exception 'Synk % finns inte', p_sync_id using errcode = 'no_data_found'; end if;
  if v_sync.status = 'succeeded' then raise exception 'Synken är redan publicerad' using errcode = 'invalid_parameter_value'; end if;
  update afr_syncs set status = 'failed', error_message = coalesce(p_reason, 'Avbruten av ETL'), last_activity_at = now() where id = p_sync_id;
  delete from afr_stage_records where sync_id = p_sync_id;
  update data_source_runs set status = 'failed', finished_at = now(), error_message = coalesce(p_reason, 'Avbruten') where id = v_sync.run_id;
  update data_source_state set last_status = 'failed', last_error = coalesce(p_reason, 'Avbruten'), last_checked_at = now(), updated_at = now()
    where source_id = 'scb-afr';
  return jsonb_build_object('sync_id', p_sync_id, 'status', 'failed');
end $$;

-- Återöppna en avbruten första laddning (idempotenta chunkar skickas om).
create or replace function public.afr_reopen_initial_sync(p_sync_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_sync afr_syncs%rowtype;
begin
  perform pg_advisory_xact_lock(hashtext('scb-afr'));
  select * into v_sync from afr_syncs where id = p_sync_id for update;
  if not found then raise exception 'Synk % finns inte', p_sync_id using errcode = 'no_data_found'; end if;
  if v_sync.mode <> 'initial' or v_sync.status not in ('failed','receiving') then
    raise exception 'Endast ofullbordad första laddning kan återöppnas' using errcode = 'invalid_parameter_value';
  end if;
  if v_sync.stats ? 'cleanup_started' then
    raise exception 'Städning har påbörjats; starta om första laddningen efter städning' using errcode = 'invalid_parameter_value';
  end if;
  if exists (select 1 from afr_syncs where status = 'receiving' and id <> p_sync_id) then
    raise exception 'En annan synk pågår' using errcode = 'invalid_parameter_value';
  end if;
  update afr_syncs set status = 'receiving', error_message = null, last_activity_at = now() where id = p_sync_id returning * into v_sync;
  update data_source_runs set status = 'started', finished_at = null, error_message = null where id = v_sync.run_id;
  return jsonb_build_object('sync_id', v_sync.id, 'je_source_count', v_sync.je_source_count, 'ae_source_count', v_sync.ae_source_count,
    'expected_je_chunks', v_sync.expected_je_chunks, 'expected_ae_chunks', v_sync.expected_ae_chunks,
    'received_je_chunks', v_sync.received_je_chunks, 'received_ae_chunks', v_sync.received_ae_chunks, 'source_date', v_sync.source_date);
end $$;

-- Städa en misslyckad första laddning i begränsade steg.
create or replace function public.afr_cleanup_failed_initial(p_sync_id uuid, p_max_rows integer default 20000)
returns jsonb language plpgsql security definer set search_path = public set statement_timeout = '60s' as $$
declare v_sync afr_syncs%rowtype; v_n integer := 0; v_m integer; v_remaining boolean;
begin
  if p_max_rows < 1 or p_max_rows > 50000 then raise exception 'p_max_rows 1..50000' using errcode = 'invalid_parameter_value'; end if;
  select * into v_sync from afr_syncs where id = p_sync_id for update;
  if not found then raise exception 'Synk % finns inte', p_sync_id using errcode = 'no_data_found'; end if;
  if v_sync.mode <> 'initial' or v_sync.status <> 'failed' then
    raise exception 'Endast misslyckad första laddning kan städas' using errcode = 'invalid_parameter_value';
  end if;
  update afr_syncs set stats = stats || jsonb_build_object('cleanup_started', now()), last_activity_at = now() where id = p_sync_id;

  delete from afr_ae_current where cfar_nr in (select cfar_nr from afr_ae_current where sync_id = p_sync_id limit p_max_rows);
  get diagnostics v_m = row_count; v_n := v_n + v_m;
  if v_n < p_max_rows then
    delete from afr_ae_history where history_id in (select history_id from afr_ae_history where sync_id = p_sync_id limit p_max_rows - v_n);
    get diagnostics v_m = row_count; v_n := v_n + v_m;
  end if;
  if v_n < p_max_rows then
    delete from afr_je_current where je_id in (select je_id from afr_je_current where sync_id = p_sync_id limit p_max_rows - v_n);
    get diagnostics v_m = row_count; v_n := v_n + v_m;
  end if;
  if v_n < p_max_rows then
    delete from afr_je_history where history_id in (select history_id from afr_je_history where sync_id = p_sync_id limit p_max_rows - v_n);
    get diagnostics v_m = row_count; v_n := v_n + v_m;
  end if;

  v_remaining := exists (select 1 from afr_ae_current where sync_id = p_sync_id) or exists (select 1 from afr_ae_history where sync_id = p_sync_id)
    or exists (select 1 from afr_je_current where sync_id = p_sync_id) or exists (select 1 from afr_je_history where sync_id = p_sync_id);
  if not v_remaining then delete from afr_sync_chunks where sync_id = p_sync_id; end if;
  return jsonb_build_object('sync_id', p_sync_id, 'deleted_rows', v_n, 'remaining', v_remaining);
end $$;

-- Nuvarande id + hash för ETL:s delta (endast poster som finns i källan).
create or replace function public.afr_current_hashes(p_entity text, p_after text default null, p_limit integer default 50000)
returns jsonb language plpgsql stable security definer set search_path = public set statement_timeout = '60s' as $$
declare v_items jsonb; v_last text;
begin
  if p_limit < 1 or p_limit > 100000 then raise exception 'p_limit 1..100000' using errcode = 'invalid_parameter_value'; end if;
  if p_entity = 'je' then
    select coalesce(jsonb_agg(jsonb_build_array(k, h) order by k collate "C"), '[]'::jsonb), max(k collate "C") into v_items, v_last
    from (select i.pe_org_nr k, c.row_hash h from afr_je_current c join afr_je_ident i on i.je_id = c.je_id
          where c.in_source and (p_after is null or i.pe_org_nr collate "C" > p_after collate "C")
          order by i.pe_org_nr collate "C" limit p_limit) s;
  elsif p_entity = 'ae' then
    select coalesce(jsonb_agg(jsonb_build_array(k::text, h) order by k), '[]'::jsonb), max(k)::text into v_items, v_last
    from (select c.cfar_nr k, c.row_hash h from afr_ae_current c
          where c.in_source and (p_after is null or c.cfar_nr > p_after::bigint)
          order by c.cfar_nr limit p_limit) s;
  else
    raise exception 'Okänd entitet' using errcode = 'invalid_parameter_value';
  end if;
  return jsonb_build_object('items', v_items, 'next_after', v_last, 'has_more', jsonb_array_length(v_items) = p_limit);
end $$;

-- Kodtabeller: upptäck och logga ändringar.
create or replace function public.afr_sync_code_table(p_table text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_added integer; v_changed integer; v_removed integer; v_react integer;
begin
  if p_table not in ('naringsgrenkoder','kommunkoder','lankoder','ftgstatkoder','anstklkoder','arbgivstatkoder','aetypkoder',
    'jurformkoder','omsklkoder','agarkontrollkoder','momsstatkoder','fskattstatkoder','bolstatkoder','privpublkoder',
    'sektorkoder','aestatkoder','hjverksjekoder') then
    raise exception 'Okänd eller ej tillåten kodtabell %', p_table using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception 'Kodtabellen är tom' using errcode = 'invalid_parameter_value';
  end if;

  create temp table _codes on commit drop as
    select distinct on (r->>'kod') r->>'kod' kod, r->>'klartext' klartext, coalesce(r->'extra','{}'::jsonb) extra
    from jsonb_array_elements(p_rows) r where r->>'kod' is not null;

  with ins as (
    insert into afr_code_value_history (table_name, kod, change, new_klartext, new_extra)
    select p_table, n.kod, 'added', n.klartext, n.extra from _codes n
    where not exists (select 1 from afr_code_values v where v.table_name = p_table and v.kod = n.kod) returning 1
  ) select count(*) into v_added from ins;
  with ins as (
    insert into afr_code_value_history (table_name, kod, change, old_klartext, new_klartext, old_extra, new_extra)
    select p_table, n.kod, case when v.active then 'changed' else 'reactivated' end, v.klartext, n.klartext, v.extra, n.extra
    from _codes n join afr_code_values v on v.table_name = p_table and v.kod = n.kod
    where not v.active or v.klartext is distinct from n.klartext or v.extra is distinct from n.extra returning change
  ) select count(*) filter (where change = 'changed'), count(*) filter (where change = 'reactivated') into v_changed, v_react from ins;
  with ins as (
    insert into afr_code_value_history (table_name, kod, change, old_klartext, old_extra)
    select p_table, v.kod, 'removed', v.klartext, v.extra from afr_code_values v
    where v.table_name = p_table and v.active and not exists (select 1 from _codes n where n.kod = v.kod) returning 1
  ) select count(*) into v_removed from ins;

  update afr_code_values v set active = false, updated_at = now()
    where v.table_name = p_table and v.active and not exists (select 1 from _codes n where n.kod = v.kod);
  insert into afr_code_values (table_name, kod, klartext, extra)
    select p_table, kod, klartext, extra from _codes
    on conflict (table_name, kod) do update set klartext = excluded.klartext, extra = excluded.extra, active = true,
      updated_at = case when afr_code_values.klartext is distinct from excluded.klartext or afr_code_values.extra is distinct from excluded.extra
        or not afr_code_values.active then now() else afr_code_values.updated_at end;

  return jsonb_build_object('table', p_table, 'rows', (select count(*) from _codes), 'added', v_added,
    'changed', v_changed, 'reactivated', v_react, 'removed', v_removed);
end $$;

revoke all on function public.afr_start_sync(text, text, text, timestamptz, integer, integer, integer, integer, boolean, jsonb) from public, anon, authenticated;
revoke all on function public.afr_store_chunk(uuid, text, integer, jsonb, jsonb, text) from public, anon, authenticated;
revoke all on function public.afr_finalize_sync(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.afr_abort_sync(uuid, text) from public, anon, authenticated;
revoke all on function public.afr_reopen_initial_sync(uuid) from public, anon, authenticated;
revoke all on function public.afr_cleanup_failed_initial(uuid, integer) from public, anon, authenticated;
revoke all on function public.afr_current_hashes(text, text, integer) from public, anon, authenticated;
revoke all on function public.afr_sync_code_table(text, jsonb) from public, anon, authenticated;
grant execute on function public.afr_start_sync(text, text, text, timestamptz, integer, integer, integer, integer, boolean, jsonb) to service_role;
grant execute on function public.afr_store_chunk(uuid, text, integer, jsonb, jsonb, text) to service_role;
grant execute on function public.afr_finalize_sync(uuid, jsonb) to service_role;
grant execute on function public.afr_abort_sync(uuid, text) to service_role;
grant execute on function public.afr_reopen_initial_sync(uuid) to service_role;
grant execute on function public.afr_cleanup_failed_initial(uuid, integer) to service_role;
grant execute on function public.afr_current_hashes(text, text, integer) to service_role;
grant execute on function public.afr_sync_code_table(text, jsonb) to service_role;

-- Analysvy (förberedd, ej publik): arbetsställe med ärvda JE-attribut. Inga identifierare eller koordinater.
create view public.afr_ae_analysis with (security_invoker = true) as
select a.cfar_nr, a.lan, a.kommun, a.anst_kl, a.ae_stat, a.ae_typ, a.hj_verks_je,
  a.tat_sma_typ_kod, a.tat_ort_sma_ort_kod,
  (select s.naringsgren from public.afr_ae_sni_current s where s.cfar_nr = a.cfar_nr and s.rangordning = 1 limit 1) as primar_sni,
  a.je_id, j.ag_kat, g.grupp as agarkontroll_grupp, j.sektor, j.jurform, j.lan_sate, j.kommun_sate,
  (j.lan_sate is not null and a.lan is not null and j.lan_sate <> a.lan) as sate_utanfor_lan
from public.afr_ae_current a
left join public.afr_je_current j on j.je_id = a.je_id
left join public.afr_agkat_group g on g.ag_kat = j.ag_kat
where a.in_source and exists (select 1 from public.afr_syncs s where s.mode = 'initial' and s.status = 'succeeded');
grant select on public.afr_ae_analysis to authenticated, service_role;

insert into public.data_sources (id, provider, name, source_url, cadence, active)
values ('scb-afr', 'SCB', 'SCB Allmänna företagsregistret', 'https://apiafr.scb.se/', 'daglig', true)
on conflict (id) do nothing;
