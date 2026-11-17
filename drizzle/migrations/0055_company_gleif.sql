-- Apply manually once, not via Drizzle's automatic journal.
begin;
create table public.company_gleif_versions (
 je_id uuid not null references public.afr_je_ident(je_id),
 stage text not null check(stage in ('identity','relations')),
 payload_sha256 text not null check(payload_sha256 ~ '^[a-f0-9]{64}$'),
 payload jsonb not null, first_observed_at timestamptz not null default now(),
 first_source jsonb not null,
 primary key(je_id,stage,payload_sha256)
);
create table public.company_gleif_current (
 je_id uuid not null, stage text not null, payload_sha256 text not null,
 checked_at timestamptz not null default now(), next_check_at timestamptz not null,
 source jsonb not null,
 primary key(je_id,stage),
 foreign key(je_id,stage,payload_sha256) references public.company_gleif_versions(je_id,stage,payload_sha256)
);
do $$ declare t text; begin
 foreach t in array array['company_gleif_versions','company_gleif_current'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 execute format('grant all on public.%I to service_role',t);
 execute format('create policy admin_read on public.%I for select to authenticated using(public.has_role(auth.uid(),''admin''))',t);
 end loop;
end $$;
create function public.company_gleif_scope(p_after uuid default null)
returns jsonb language plpgsql security definer set search_path=public set statement_timeout='60s' as $$
declare result jsonb;
begin
 if not exists(select 1 from company_account_scope_state where sync_id=(select id from afr_syncs where status='succeeded' order by source_date::timestamptz desc,created_at desc limit 1)) then
   raise exception 'AFR scope cache is stale';
 end if;
 with page as materialized(
 select s.je_id,i.org_nr from company_account_scope_members s join afr_je_ident i using(je_id)
 join afr_je_current j using(je_id)
 where j.jurform is not null and j.jurform<>'10' and (p_after is null or s.je_id>p_after)
 order by s.je_id limit 500)
 select coalesce(jsonb_agg(jsonb_build_object('je_id',p.je_id,'org_nr',p.org_nr,'afr_sync_id',(select sync_id from company_account_scope_state),
 'identity',case when a.je_id is null then null else jsonb_build_object('sha256',a.payload_sha256,
   'payload',v.payload,'next_check_at',a.next_check_at,'source',a.source) end,
 'relations',case when r.je_id is null then null else jsonb_build_object('sha256',r.payload_sha256,
   'next_check_at',r.next_check_at,'source',r.source) end) order by p.je_id),'[]') into result
 from page p left join company_gleif_current a on a.je_id=p.je_id and a.stage='identity'
 left join company_gleif_versions v on (v.je_id,v.stage,v.payload_sha256)=(a.je_id,a.stage,a.payload_sha256)
 left join company_gleif_current r on r.je_id=p.je_id and r.stage='relations';
 return result;
end $$;
create function public.company_gleif_store(p_stage text,p_records jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb; dat jsonb; j uuid; sh text; org text; current_identity text; n int:=0;
begin
 if p_stage not in ('identity','relations') or jsonb_typeof(p_records)<>'array' or jsonb_array_length(p_records)>100 then raise exception 'Invalid GLEIF chunk'; end if;
 for r in select value from jsonb_array_elements(p_records) loop
  j:=(r->>'je_id')::uuid; sh:=r->>'payload_sha256'; dat:=(r->>'canonical_payload')::jsonb;
  select i.org_nr into org from company_account_scope_members s join afr_je_current c using(je_id) join afr_je_ident i using(je_id)
    where s.je_id=j and c.jurform is not null and c.jurform<>'10';
  if org is null then raise exception 'Outside legal-entity scope'; end if;
  if r->'source'->>'afr_sync_id' is distinct from (select sync_id::text from company_account_scope_state) then
    raise exception 'AFR scope changed'; end if;
  if sh is null or sh !~ '^[a-f0-9]{64}$' or encode(extensions.digest(convert_to(r->>'canonical_payload','UTF8'),'sha256'),'hex')<>sh
    or jsonb_typeof(dat->'entities') is distinct from 'array' then raise exception 'Invalid GLEIF payload'; end if;
  if p_stage='identity' then
   if dat->>'status' is null or dat->>'status' not in ('matched','not_found','ambiguous') then raise exception 'Invalid identity outcome'; end if;
   if exists(select 1 from jsonb_array_elements(dat->'entities') e where e->>'registry' is distinct from 'RA000544'
     or e->>'jurisdiction' is distinct from 'SE' or replace(e->>'registered_as','-','') is distinct from org) then raise exception 'GLEIF identity mismatch'; end if;
   if (dat->>'status'='matched') is distinct from (jsonb_array_length(dat->'entities')=1)
     or (dat->>'status'='not_found') is distinct from (jsonb_array_length(dat->'entities')=0) then raise exception 'Invalid match count'; end if;
  else
   select payload_sha256 into current_identity from company_gleif_current where je_id=j and stage='identity' for update;
   if current_identity is null or current_identity is distinct from r->'source'->>'identity_sha256' then raise exception 'Identity changed'; end if;
   if dat->>'status' is null or dat->>'status' not in ('resolved','no_exact_lei','ambiguous_lei') then raise exception 'Invalid relation outcome'; end if;
  end if;
  insert into company_gleif_versions(je_id,stage,payload_sha256,payload,first_source)
   values(j,p_stage,sh,dat,r->'source') on conflict do nothing;
  insert into company_gleif_current(je_id,stage,payload_sha256,next_check_at,source)
   values(j,p_stage,sh,now()+interval '7 days',r->'source')
   on conflict(je_id,stage) do update set payload_sha256=excluded.payload_sha256,checked_at=now(),
     next_check_at=excluded.next_check_at,source=excluded.source;
  n:=n+1;
 end loop;
 return jsonb_build_object('stored',n);
end $$;
create function public.company_gleif_coverage()
returns jsonb language sql security definer set search_path=public as $$
 with scoped as (select s.je_id from company_account_scope_members s join afr_je_current j using(je_id)
 where j.jurform is not null and j.jurform<>'10'),
 facts as(select s.je_id,a.checked_at as identity_checked_at,v.payload as identity_payload,
 r.checked_at as relation_checked_at,rv.payload as relation_payload,r.source
 from scoped s left join company_gleif_current a on a.je_id=s.je_id and a.stage='identity'
 left join company_gleif_versions v on (v.je_id,v.stage,v.payload_sha256)=(a.je_id,a.stage,a.payload_sha256)
 left join company_gleif_current r on r.je_id=s.je_id and r.stage='relations' and r.source->>'identity_sha256'=a.payload_sha256
 left join company_gleif_versions rv on (rv.je_id,rv.stage,rv.payload_sha256)=(r.je_id,r.stage,r.payload_sha256))
 select jsonb_build_object('scope',count(*),'identity_checked',count(identity_checked_at),
 'matched',count(*) filter(where identity_payload->>'status'='matched'),
 'not_found',count(*) filter(where identity_payload->>'status'='not_found'),
 'ambiguous',count(*) filter(where identity_payload->>'status'='ambiguous'),
 'relations_checked',count(relation_checked_at),
 'with_parent',count(*) filter(where relation_payload->'entities'->0->'direct'->>'state'='relation'
  or relation_payload->'entities'->0->'ultimate'->>'state'='relation'),
 'with_reporting_exception',count(*) filter(where relation_payload->'entities'->0->'direct'->>'state'='exception'
  or relation_payload->'entities'->0->'ultimate'->>'state'='exception'),
 'last_relation_check',max(relation_checked_at)) from facts;
$$;
revoke all on function public.company_gleif_scope(uuid),public.company_gleif_store(text,jsonb),public.company_gleif_coverage() from public,anon,authenticated;
grant execute on function public.company_gleif_scope(uuid),public.company_gleif_store(text,jsonb),public.company_gleif_coverage() to service_role;
insert into public.data_sources(id,provider,name,source_url,cadence,active)
 values('gleif-parent-relations','GLEIF','GLEIF – LEI och koncernrelationer','https://www.gleif.org/en/lei-data/gleif-api','weekly',true) on conflict do nothing;
insert into public.data_source_state(source_id) values('gleif-parent-relations') on conflict do nothing;
commit;
