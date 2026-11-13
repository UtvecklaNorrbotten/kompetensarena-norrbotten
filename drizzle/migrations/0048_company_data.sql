-- Protected enrichment: no changes to AFR's canonical hashes or core history.
begin;
create table public.afr_profile_versions (
 id bigint generated always as identity primary key,
 entity text not null check(entity in ('je','ae')), entity_id text not null,
 payload jsonb not null, payload_hash text not null,
 source_date text not null, observed_at timestamptz not null,
 sync_id uuid not null references public.afr_syncs(id),
 change_types text[] not null
);
create index afr_profile_versions_entity_idx on public.afr_profile_versions(entity,entity_id,id desc);
create table public.afr_profile_current (
 entity text not null check(entity in ('je','ae')), entity_id text not null,
 version_id bigint not null references public.afr_profile_versions(id),
 payload_hash text not null, contact jsonb not null, contact_hash text not null,
 source_date text not null, observed_at timestamptz not null,
 primary key(entity,entity_id)
);
create table public.afr_profile_releases (
 sync_id uuid primary key references public.afr_syncs(id),
 source_date text not null, completed_at timestamptz not null default now(),
 details jsonb not null
);
create table public.company_account_archives (
 archive_key text primary key, etag text not null, size bigint not null,
 source_modified timestamptz not null, scope_hash text not null,
 scanned_at timestamptz not null default now(), members integer not null,
 selected integer not null, downloaded_bytes bigint not null
);
-- One latest available candidate per company; older documents are not imported.
create table public.company_account_candidates (
 je_id uuid primary key references public.afr_je_ident(je_id),
 period_end date not null, archive_key text not null, member_name text not null,
 archive_etag text not null, archive_size bigint not null, source_modified timestamptz not null,
 status text not null default 'pending' check(status in ('pending','imported','quarantined')),
 error_code text, package_sha256 text, checked_parser_version text, alternatives jsonb not null default '[]', checked_at timestamptz
);
create table public.company_accounts (
 id bigint generated always as identity primary key,
 je_id uuid not null references public.afr_je_ident(je_id),
 document_id text not null, source_reference text not null,
 archive_key text not null, member_name text not null, source_modified timestamptz not null,
 package_sha256 text not null check(package_sha256 ~ '^[0-9a-f]{64}$'),
 document_sha256 text not null check(document_sha256 ~ '^[0-9a-f]{64}$'),
 storage_path text not null, parser_version text not null,
 period_start date not null, period_end date not null check(period_end>=period_start),
 currency text not null, unit text not null,
 report_type text not null, scope text not null check(scope='company'),
 net_sales numeric, operating_profit numeric, profit_for_year numeric,
 equity numeric, total_assets numeric, average_employees numeric,
 operating_margin numeric generated always as (100*operating_profit/nullif(net_sales,0)) stored,
 equity_ratio numeric generated always as (100*equity/nullif(total_assets,0)) stored,
 provenance jsonb not null, issues jsonb not null,
 allocation_sync_id uuid references public.afr_syncs(id),
 observed_at timestamptz not null default now(),
 unique(je_id,package_sha256,document_sha256,parser_version)
);
create table public.company_accounts_latest (
 je_id uuid primary key references public.afr_je_ident(je_id),
 account_id bigint not null references public.company_accounts(id)
);
create table public.company_account_allocations (
 account_id bigint not null references public.company_accounts(id),
 cfar_nr bigint not null, structure_history_id bigint references public.afr_ae_history(history_id),
 weight numeric not null check(weight>=0 and weight<=1),
 estimated_net_sales numeric, flags text[] not null,
 structure_basis text not null, structure_sync_id uuid not null references public.afr_syncs(id),
 rule_version text not null default 'afr-midpoint-1', is_estimate boolean not null default true check(is_estimate),
 primary key(account_id,cfar_nr)
);
create index company_accounts_company_idx on public.company_accounts(je_id,period_end desc);
-- Required for finding all historical CFARs owned by one company.
create index if not exists afr_ae_history_je_cfar_idx on public.afr_ae_history(je_id,cfar_nr);
create index if not exists afr_ae_current_je_idx on public.afr_ae_current(je_id);

-- Every new relation is admin/ETL only, including source documents.
do $$ declare t text; begin
 foreach t in array array['afr_profile_versions','afr_profile_current','afr_profile_releases',
 'company_account_archives','company_account_candidates','company_accounts','company_accounts_latest','company_account_allocations'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('grant all on public.%I to service_role',t);
  execute format('create policy admin_read on public.%I for select to authenticated using(public.has_role(auth.uid(),''admin''))',t);
 end loop;
end $$;
grant usage,select on sequence public.afr_profile_versions_id_seq,public.company_accounts_id_seq to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('company-source-documents','company-source-documents',false,40000000,array['application/zip'])
on conflict(id) do nothing;
-- No anon/authenticated object policy: documents may contain personal data.
insert into public.data_sources(id,provider,name,source_url,cadence,active) values
 ('scb-afr-profiles','SCB','AFR – namn, adresser och registermarkeringar','https://apiafr.scb.se','daily',true),
 ('bolagsverket-annual-accounts','Bolagsverket','Digitala årsredovisningar – senaste bokslut','https://vardefulla-datamangder.bolagsverket.se/arsredovisningar/','weekly',true)
on conflict(id) do nothing;
insert into public.data_source_state(source_id) values('scb-afr-profiles'),('bolagsverket-annual-accounts') on conflict do nothing;

-- Canonical object text supplied by ETL is parsed and checked before hashing.
-- No JSONB rendering assumptions or locale-sensitive numeric conversions.
create function public.afr_profile_store(p_sync_id uuid,p_entity text,p_records jsonb)
returns jsonb language plpgsql security definer set search_path=public set statement_timeout='120s' as $$
declare s afr_syncs%rowtype; r jsonb; eid text; old afr_profile_current%rowtype;
 prev jsonb; dat jsonb; con jsonb; ph text; ch text; vid bigint; changes text[]; n int:=0; contacts int:=0;
begin
 perform pg_advisory_xact_lock(hashtext('afr-profiles'));
 select * into strict s from afr_syncs where id=p_sync_id and status='succeeded';
 if exists(select 1 from afr_syncs where status='succeeded' and fetched_at>s.fetched_at) then raise exception 'Core AFR advanced during profile enrichment'; end if;
 if p_entity not in ('je','ae') or jsonb_typeof(p_records)<>'array' or jsonb_array_length(p_records)>1000 then
  raise exception 'Invalid profile chunk'; end if;
 if exists(select 1 from afr_profile_releases x join afr_syncs sx on sx.id=x.sync_id
           where sx.fetched_at>s.fetched_at) then raise exception 'Stale profile source'; end if;
 for r in select value from jsonb_array_elements(p_records) loop
  if p_entity='je' then
   select i.je_id::text into eid from afr_je_ident i join afr_je_current c using(je_id) where i.pe_org_nr=r->>'key' and c.in_source;
  else
   select cfar_nr::text into eid from afr_ae_current where cfar_nr=(r->>'key')::bigint and in_source;
  end if;
  if eid is null then raise exception 'Profile identity absent from published AFR'; end if;
  dat:=(r->>'profile_canonical')::jsonb; con:=(r->>'contact_canonical')::jsonb;
  if jsonb_typeof(dat)<>'object' or jsonb_typeof(con)<>'object' then raise exception 'Invalid profile object'; end if;
  if exists(select 1 from jsonb_object_keys(dat) k where k not in ('namn','foretagsnamn','ben','postAdress','belagenhetsadress','address_coordinates','expImp'))
   or exists(select 1 from jsonb_object_keys(con) k where k not in ('tel','epost')) then raise exception 'Unknown profile field'; end if;
  ph:=afr_hash(r->>'profile_canonical'); ch:=afr_hash(r->>'contact_canonical');
  if ph<>r->>'profile_hash' or ch<>r->>'contact_hash' then raise exception 'Profile checksum mismatch'; end if;
  select * into old from afr_profile_current where entity=p_entity and entity_id=eid;
  if old.observed_at>s.fetched_at then raise exception 'Out of order profile observation'; end if;
  if old.payload_hash is distinct from ph then
   select payload into prev from afr_profile_versions where id=old.version_id;
   changes:=case when old.version_id is null then array['första_observation'] else array_remove(array[
    case when prev->'namn' is distinct from dat->'namn' or prev->'foretagsnamn' is distinct from dat->'foretagsnamn' or prev->'ben' is distinct from dat->'ben' then 'namnbyte' end,
    case when prev->'postAdress' is distinct from dat->'postAdress' then 'ändrad_postadress' end,
    case when prev->'belagenhetsadress' is distinct from dat->'belagenhetsadress' then 'ändrad_besöksadress' end,
    case when prev->'address_coordinates' is distinct from dat->'address_coordinates' then 'ändrade_adresskoordinater' end,
    case when prev#>>'{address_coordinates,nordKoordinatAdressSW}' is not null and dat#>>'{address_coordinates,nordKoordinatAdressSW}' is not null
      and prev#>>'{address_coordinates,ostKoordinatAdressSW}' is not null and dat#>>'{address_coordinates,ostKoordinatAdressSW}' is not null
      and prev->'address_coordinates' is distinct from dat->'address_coordinates' then 'möjlig_fysisk_flytt' end,
    case when prev->>'expImp'='N' and dat->>'expImp'='J' then 'tillkomst_export_importmarkering_i_registret'
      when prev->>'expImp'='J' and dat->>'expImp'='N' then 'bortfall_export_importmarkering_i_registret'
      when prev->'expImp' is distinct from dat->'expImp' then 'ändrad_export_importmarkering_i_registret' end
   ]::text[],null) end;
   insert into afr_profile_versions(entity,entity_id,payload,payload_hash,source_date,observed_at,sync_id,change_types)
    values(p_entity,eid,dat,ph,s.source_date,s.fetched_at,p_sync_id,changes) returning id into vid;
   n:=n+1;
  else vid:=old.version_id; end if;
  if old.contact_hash is distinct from ch then contacts:=contacts+1; end if;
  insert into afr_profile_current(entity,entity_id,version_id,payload_hash,contact,contact_hash,source_date,observed_at)
   values(p_entity,eid,vid,ph,con,ch,s.source_date,s.fetched_at)
   on conflict(entity,entity_id) do update set version_id=excluded.version_id,payload_hash=excluded.payload_hash,
    contact=excluded.contact,contact_hash=excluded.contact_hash,source_date=excluded.source_date,observed_at=excluded.observed_at;
 end loop;
 return jsonb_build_object('versions',n,'contacts_updated',contacts);
end $$;

create function public.company_data_scope(p_after uuid default null,p_limit int default 1000)
returns jsonb language sql stable security definer set search_path=public set statement_timeout='120s' set enable_nestloop='off' set enable_mergejoin='off' as $$
 with ids as (select je_id from afr_je_current where in_source and lan_sate='25' and (p_after is null or je_id>p_after)
 union select je_id from afr_ae_current where in_source and lan='25' and (p_after is null or je_id>p_after)), page_ids as materialized (
 select je_id from ids order by je_id limit least(greatest(p_limit,1),2000)), page as (
 select i.je_id,i.org_nr,c.ae_ant from page_ids x join afr_je_ident i using(je_id) join afr_je_current c using(je_id) where c.in_source)
 select coalesce(jsonb_agg(to_jsonb(page) order by je_id),'[]') from page
$$;

create function public.company_account_structure(p_je_id uuid,p_period_end date)
returns jsonb language plpgsql stable security definer set search_path=public set statement_timeout='120s' as $$
declare first_date date; latest_sync uuid; rows jsonb; basis text;
begin
 select min(source_date::timestamptz::date) into first_date from afr_syncs where status='succeeded';
 select id into latest_sync from afr_syncs where status='succeeded' order by source_date::timestamptz desc,created_at desc limit 1;
 if first_date>p_period_end then
  basis:='current_structure_for_older_accounts';
  select coalesce(jsonb_agg(jsonb_build_object('cfar_nr',cfar_nr::text,'history_id',current_history_id,'anst_kl',anst_kl) order by cfar_nr),'[]') into rows
   from afr_ae_current where je_id=p_je_id and in_source;
 else
  basis:='historical_source_snapshot';
  with cfars as (select distinct cfar_nr from afr_ae_history where je_id=p_je_id), states as (
   select h.* from cfars c cross join lateral (
    select h.* from afr_ae_history h join afr_syncs s on s.id=h.sync_id
    where h.cfar_nr=c.cfar_nr and s.status='succeeded' and s.source_date::timestamptz::date<=p_period_end
    order by h.valid_from desc,h.history_id desc limit 1) h)
  select coalesce(jsonb_agg(jsonb_build_object('cfar_nr',cfar_nr::text,'history_id',history_id,'anst_kl',anst_kl) order by cfar_nr),'[]') into rows
   from states where je_id=p_je_id and in_source;
 end if;
 return jsonb_build_object('basis',basis,'sync_id',latest_sync,'establishments',rows);
end $$;

create function public.company_account_store(p_je_id uuid,p_document jsonb,p_allocations jsonb,p_structure jsonb)
returns jsonb language plpgsql security definer set search_path=public set statement_timeout='120s' as $$
declare aid bigint; d jsonb:=p_document; m jsonb:=d->'metrics'; candidate company_account_candidates%rowtype;
 expected jsonb; ar jsonb; n int;
begin
 perform pg_advisory_xact_lock(hashtext('company-account:'||p_je_id::text));
 select * into strict candidate from company_account_candidates where je_id=p_je_id for update;
 if candidate.archive_key<>d->>'archive_key' or candidate.member_name<>d->>'member_name' or candidate.archive_etag<>d->>'archive_etag'
    or candidate.period_end<>(d->>'period_end')::date then raise exception 'Candidate changed during import'; end if;
 if d->>'scope'<>'company' or d->>'storage_path'<>'accounts/'||(d->>'package_sha256')||'.zip' then raise exception 'Invalid document scope/path'; end if;
 if exists(select 1 from jsonb_object_keys(m) k where k not in ('net_sales','operating_profit','profit_for_year','equity','total_assets','average_employees')) then raise exception 'Unknown account metric'; end if;
 if not exists(select 1 from storage.objects where bucket_id='company-source-documents' and name=d->>'storage_path') then raise exception 'Source package not archived'; end if;
 expected:=company_account_structure(p_je_id,(d->>'period_end')::date);
 if expected is distinct from p_structure then raise exception 'AFR structure changed during allocation'; end if;
 n:=jsonb_array_length(expected->'establishments');
 if jsonb_array_length(p_allocations)<>n or (n>0 and (select sum((v->>'weight')::numeric) from jsonb_array_elements(p_allocations) v)<>1) then raise exception 'Allocation count or weight sum mismatch'; end if;
 if (select count(distinct v->>'cfar_nr') from jsonb_array_elements(p_allocations) v)<>n then raise exception 'Duplicate allocation CFAR'; end if;
 if exists(select 1 from jsonb_array_elements(p_allocations) a where not exists(select 1 from jsonb_array_elements(expected->'establishments') e where e->>'cfar_nr'=a->>'cfar_nr' and e->>'history_id'=a->>'structure_history_id')) then raise exception 'Allocation denominator excludes Swedish establishments'; end if;
 if m->>'net_sales' is null then
  if exists(select 1 from jsonb_array_elements(p_allocations) a where a->>'estimated_net_sales' is not null) then raise exception 'Missing sales must remain null'; end if;
 elsif n>0 and (select sum((v->>'estimated_net_sales')::numeric) from jsonb_array_elements(p_allocations) v)<>(m->>'net_sales')::numeric then raise exception 'Allocated sales do not sum to company sales'; end if;
 insert into company_accounts(je_id,document_id,source_reference,archive_key,member_name,source_modified,package_sha256,document_sha256,storage_path,parser_version,
 period_start,period_end,currency,unit,report_type,scope,net_sales,operating_profit,profit_for_year,equity,total_assets,average_employees,provenance,issues)
 values(p_je_id,d->>'document_id',d->>'source_reference',d->>'archive_key',d->>'member_name',candidate.source_modified,d->>'package_sha256',d->>'document_sha256',d->>'storage_path',d->>'parser_version',
 (d->>'period_start')::date,(d->>'period_end')::date,d->>'currency',d->>'unit',d->>'report_type',d->>'scope',(m->>'net_sales')::numeric,(m->>'operating_profit')::numeric,(m->>'profit_for_year')::numeric,
 (m->>'equity')::numeric,(m->>'total_assets')::numeric,(m->>'average_employees')::numeric,d->'provenance',d->'issues')
 on conflict(je_id,package_sha256,document_sha256,parser_version) do update set parser_version=excluded.parser_version returning id into aid;
 delete from company_account_allocations where account_id=aid;
 insert into company_account_allocations(account_id,cfar_nr,structure_history_id,weight,estimated_net_sales,flags,structure_basis,structure_sync_id)
 select aid,(a->>'cfar_nr')::bigint,(a->>'structure_history_id')::bigint,(a->>'weight')::numeric,(a->>'estimated_net_sales')::numeric,
 array(select jsonb_array_elements_text(a->'flags')),expected->>'basis',(expected->>'sync_id')::uuid from jsonb_array_elements(p_allocations) a;
 update company_accounts set allocation_sync_id=(expected->>'sync_id')::uuid where id=aid;
 insert into company_accounts_latest(je_id,account_id) values(p_je_id,aid) on conflict(je_id) do update set account_id=excluded.account_id;
 update company_account_candidates set status='imported',error_code=null,package_sha256=d->>'package_sha256',checked_parser_version=d->>'parser_version',checked_at=now() where je_id=p_je_id;
 return jsonb_build_object('account_id',aid,'allocations',n);
end $$;

-- Latest accounts are read only through this pointer: corrections cannot double count.
-- Missing/zero denominators produce NULL ratios. Equity ratio is unadjusted equity/assets.
comment on column public.company_accounts.equity_ratio is '100 * eget kapital / totala tillgångar. Ej justerat för obeskattade reserver. NULL vid noll/saknad nämnare.';
comment on column public.company_accounts.operating_margin is '100 * rörelseresultat / nettoomsättning. NULL vid noll/saknad nämnare.';
do $$ declare f record; begin
 for f in select oid::regprocedure sig from pg_proc where pronamespace='public'::regnamespace
 and proname in ('afr_profile_store','company_data_scope','company_account_structure','company_account_store') loop
  execute format('revoke all on function %s from public,anon,authenticated',f.sig);
  execute format('grant execute on function %s to service_role',f.sig);
 end loop;
end $$;

create function public.company_account_catalog(p_archive jsonb,p_candidates jsonb)
returns jsonb language plpgsql security definer set search_path=public set statement_timeout='120s' as $$
declare r jsonb; old company_account_candidates%rowtype; newer text; older text;
begin
 perform pg_advisory_xact_lock(hashtext('company-account-catalog'));
 for r in select value from jsonb_array_elements(p_candidates) loop
  select * into old from company_account_candidates where je_id=(r->>'je_id')::uuid for update;
  newer:=split_part(p_archive->>'key','_',1); older:=split_part(old.archive_key,'_',1);
  if old.je_id is null or (r->>'period_end')::date>old.period_end or
   ((r->>'period_end')::date=old.period_end and newer>older) then
   insert into company_account_candidates(je_id,period_end,archive_key,member_name,archive_etag,archive_size,source_modified)
   values((r->>'je_id')::uuid,(r->>'period_end')::date,p_archive->>'key',r->>'member_name',p_archive->>'etag',(p_archive->>'size')::bigint,(p_archive->>'modified')::timestamptz)
   on conflict(je_id) do update set period_end=excluded.period_end,archive_key=excluded.archive_key,member_name=excluded.member_name,
    archive_etag=excluded.archive_etag,archive_size=excluded.archive_size,source_modified=excluded.source_modified,status='pending',error_code=null,package_sha256=null,checked_parser_version=null,alternatives='[]',checked_at=null;
  elsif (r->>'period_end')::date=old.period_end and newer=older and (old.archive_key<>p_archive->>'key' or old.member_name<>r->>'member_name') then
   update company_account_candidates set status='quarantined',error_code='same_week_multiple_reports',alternatives=alternatives||jsonb_build_array(
    jsonb_build_object('archive_key',p_archive->>'key','member_name',r->>'member_name','etag',p_archive->>'etag')) where je_id=old.je_id;
  elsif old.archive_key=p_archive->>'key' and old.member_name=r->>'member_name' and old.archive_etag<>p_archive->>'etag' then
   update company_account_candidates set archive_etag=p_archive->>'etag',archive_size=(p_archive->>'size')::bigint,
    source_modified=(p_archive->>'modified')::timestamptz,status='pending',error_code=null,package_sha256=null,checked_parser_version=null,checked_at=null where je_id=old.je_id;
  end if;
 end loop;
 insert into company_account_archives(archive_key,etag,size,source_modified,scope_hash,members,selected,downloaded_bytes)
 values(p_archive->>'key',p_archive->>'etag',(p_archive->>'size')::bigint,(p_archive->>'modified')::timestamptz,p_archive->>'scope_hash',
 (p_archive->>'members')::int,jsonb_array_length(p_candidates),(p_archive->>'downloaded_bytes')::bigint)
 on conflict(archive_key) do update set etag=excluded.etag,size=excluded.size,source_modified=excluded.source_modified,scope_hash=excluded.scope_hash,
 scanned_at=now(),members=excluded.members,selected=excluded.selected,downloaded_bytes=excluded.downloaded_bytes;
 return jsonb_build_object('selected',jsonb_array_length(p_candidates));
end $$;
revoke all on function public.company_account_catalog(jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.company_account_catalog(jsonb,jsonb) to service_role;

create function public.company_data_coverage()
returns jsonb language sql stable security definer set search_path=public set statement_timeout='120s' set enable_nestloop='off' set enable_mergejoin='off' as $$
 with ids as (select je_id from afr_je_current where in_source and lan_sate='25'
 union select je_id from afr_ae_current where in_source and lan='25'), establishments as (
 select a.je_id,count(*) n from afr_ae_current a join ids i using(je_id) where a.in_source group by a.je_id),
 latest as (select a.* from company_accounts_latest l join company_accounts a on a.id=l.account_id
 join ids i on i.je_id=l.je_id join company_account_candidates c on c.je_id=l.je_id
 where c.status='imported' and c.package_sha256=a.package_sha256),
 alloc as (select x.* from company_account_allocations x join latest a on a.id=x.account_id),
 gaps as (select error_code,count(*) n from company_account_candidates c join ids i using(je_id) where status='quarantined' group by error_code)
 select jsonb_build_object('scope_companies',(select count(*) from ids),
 'single_establishment',(select count(*) from establishments where n=1),
 'multiple_establishments',(select count(*) from establishments where n>1),
 'without_establishments',(select count(*) from ids i where not exists(select 1 from establishments e where e.je_id=i.je_id)),
 'candidates',(select count(*) from company_account_candidates c join ids i using(je_id)),
 'imported_latest',(select count(*) from latest),
 'without_digital_candidate',(select count(*) from ids i where not exists(select 1 from company_account_candidates c where c.je_id=i.je_id)),
 'pending',(select count(*) from company_account_candidates c join ids i using(je_id) where status='pending'),
 'quarantine_reasons',coalesce((select jsonb_object_agg(error_code,n) from gaps),'{}'::jsonb),
 'period_end_min',(select min(period_end) from latest),'period_end_max',(select max(period_end) from latest),
 'missing_metrics',jsonb_build_object('net_sales',(select count(*) from latest where net_sales is null),
 'operating_profit',(select count(*) from latest where operating_profit is null),'profit_for_year',(select count(*) from latest where profit_for_year is null),
 'equity',(select count(*) from latest where equity is null),'total_assets',(select count(*) from latest where total_assets is null),
 'average_employees',(select count(*) from latest where average_employees is null)),
 'allocated_establishments',(select count(*) from alloc),
 'historical_structure',(select count(distinct account_id) from alloc where structure_basis='historical_source_snapshot'),
 'current_structure_for_older_accounts',(select count(distinct account_id) from alloc where structure_basis='current_structure_for_older_accounts'),
 'allocation_rules',coalesce((select jsonb_object_agg(flag,n) from (select flag,count(*) n from alloc a cross join lateral unnest(a.flags) flag group by flag) q),'{}'::jsonb),
 'weight_sum_errors',(select count(*) from (select account_id from alloc group by account_id having sum(weight)<>1) q),
 'archives_scanned',(select count(*) from company_account_archives))
$$;
revoke all on function public.company_data_coverage() from public,anon,authenticated;
grant execute on function public.company_data_coverage() to service_role;

create function public.afr_profile_hashes(p_entity text,p_keys jsonb)
returns jsonb language sql stable security definer set search_path=public as $$
 with keys as (select jsonb_array_elements_text(p_keys) k), identities as (
 select k,i.je_id::text eid from keys join afr_je_ident i on i.pe_org_nr=k where p_entity='je'
 union all select k,k from keys where p_entity='ae')
 select coalesce(jsonb_agg(jsonb_build_array(i.k,c.payload_hash,c.contact_hash)),'[]')
 from identities i join afr_profile_current c on c.entity=p_entity and c.entity_id=i.eid
$$;
revoke all on function public.afr_profile_hashes(text,jsonb) from public,anon,authenticated;
grant execute on function public.afr_profile_hashes(text,jsonb) to service_role;
create function public.company_accounts_prepare(p_parser_version text)
returns jsonb language plpgsql security definer set search_path=public set statement_timeout='120s' as $$
declare sid uuid; n int;
begin
 select id into sid from afr_syncs where status='succeeded' order by source_date::timestamptz desc,created_at desc limit 1;
 update company_account_candidates c set status='pending'
 where (c.status='quarantined' and c.error_code<>'same_week_multiple_reports' and c.checked_parser_version is distinct from p_parser_version)
 or (c.status='imported' and exists(select 1 from company_accounts_latest l join company_accounts a on a.id=l.account_id
 where l.je_id=c.je_id and (a.parser_version<>p_parser_version or a.allocation_sync_id is distinct from sid)));
 get diagnostics n=row_count;
 return jsonb_build_object('requeued',n);
end $$;
revoke all on function public.company_accounts_prepare(text) from public,anon,authenticated;
grant execute on function public.company_accounts_prepare(text) to service_role;

create view public.afr_protected_change_events with (security_invoker=true) as
 select 'profile:'||v.id as event_id,v.entity,v.entity_id,v.source_date,v.observed_at,v.change_types
 from afr_profile_versions v
 union all
 select 'core_je:'||h.history_id,'je',h.je_id::text,s.source_date,h.valid_from,array['ändrat_säte']
 from afr_je_history h join afr_syncs s on s.id=h.sync_id where 'säte'=any(h.change_types)
 union all
 select 'core_ae:'||h.history_id,'ae',h.cfar_nr::text,s.source_date,h.valid_from,
 array_remove(array[case when 'juridisk_enhet'=any(h.change_types) then 'byte_av_juridisk_enhet' end,
 case when 'geografi'=any(h.change_types) then 'ändrad_geografisk_placering' end]::text[],null)
 from afr_ae_history h join afr_syncs s on s.id=h.sync_id
 where h.change_types && array['juridisk_enhet','geografi'];
revoke all on public.afr_protected_change_events from public,anon,authenticated;
grant select on public.afr_protected_change_events to authenticated,service_role;
commit;
