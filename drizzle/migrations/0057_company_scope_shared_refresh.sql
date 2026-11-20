-- Applied manually; not journaled for replay. Scope only; no financial/history reset.
begin;
create or replace function public.company_data_refresh_scope()
returns void language plpgsql security definer set search_path=public
set statement_timeout='120s' as $$
declare sid uuid; desired uuid[];
begin
 select id into sid from afr_syncs where status='succeeded'
 order by source_date::timestamptz desc,created_at desc limit 1;
 if sid is null then raise exception 'No published AFR source'; end if;
 if exists(select 1 from company_account_scope_state where singleton and sync_id=sid) then return; end if;
 perform pg_advisory_xact_lock(hashtext('company-account-scope'));
 -- Re-read after waiting: never replace a newer cache with a previously read sync.
 select id into sid from afr_syncs where status='succeeded'
 order by source_date::timestamptz desc,created_at desc limit 1;
 if exists(select 1 from company_account_scope_state where singleton and sync_id=sid) then return; end if;
 -- Only membership deltas are changed. The API's safeupdate guard requires a
 -- genuine WHERE predicate; unfiltered DELETE was the source of SQLSTATE 21000.
 select array_agg(je_id) into desired from (
  select je_id from afr_je_current where in_source and lan_sate='25'
  union select je_id from afr_ae_current where in_source and ae_stat=1 and lan='25'
 ) expected;
 if coalesce(cardinality(desired),0)=0 then raise exception 'Empty expected company scope'; end if;
 if sid is distinct from (select id from afr_syncs where status='succeeded'
  order by source_date::timestamptz desc,created_at desc limit 1) then
  raise exception using errcode='40001',message='AFR publication changed during scope refresh';
 end if;
 delete from company_account_scope_members m
 where not exists(select 1 from unnest(desired) as expected(je_id) where expected.je_id=m.je_id);
 insert into company_account_scope_members(je_id)
 select unnest(desired) on conflict(je_id) do nothing;
 -- Publish the singleton marker atomically with the membership delta.
 update company_account_scope_state set sync_id=sid,refreshed_at=now() where singleton;
 if not found then insert into company_account_scope_state(singleton,sync_id) values(true,sid); end if;
end $$;
revoke all on function public.company_data_refresh_scope() from public,anon,authenticated;
grant execute on function public.company_data_refresh_scope() to service_role;
CREATE OR REPLACE FUNCTION public.company_data_scope(p_after uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 1000)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '120s'
 SET enable_nestloop TO 'on'
 SET enable_mergejoin TO 'on'
AS $function$
declare result jsonb;
begin
 perform company_data_refresh_scope();
 with page as materialized(select je_id from company_account_scope_members where p_after is null or je_id>p_after order by je_id limit least(greatest(p_limit,1),2000)),
 records as (select i.je_id,i.org_nr from page p join afr_je_ident i using(je_id))
 select coalesce(jsonb_agg(to_jsonb(records) order by je_id),'[]') into result from records;
 return result;
end $function$
;
CREATE OR REPLACE FUNCTION public.company_gleif_scope(p_after uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '60s'
AS $function$
declare result jsonb;
begin
 perform company_data_refresh_scope();
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
end $function$
;
commit;
