-- Applied 2026-11-13: only SCB aeStat=1 establishments enter financial
-- scope/allocation. Core AFR and profile history retain all register records.
begin;
CREATE OR REPLACE FUNCTION public.company_account_structure(p_je_id uuid, p_period_end date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '120s'
AS $function$
declare first_date date; latest_sync uuid; rows jsonb; basis text;
begin
 select min(source_date::timestamptz::date) into first_date from afr_syncs where status='succeeded';
 select id into latest_sync from afr_syncs where status='succeeded' order by source_date::timestamptz desc,created_at desc limit 1;
 if first_date>p_period_end then
  basis:='current_structure_for_older_accounts';
  select coalesce(jsonb_agg(jsonb_build_object('cfar_nr',cfar_nr::text,'history_id',current_history_id,'anst_kl',anst_kl,'ae_typ',ae_typ) order by cfar_nr),'[]') into rows
   from afr_ae_current where je_id=p_je_id and in_source and ae_stat=1;
 else
  basis:='historical_source_snapshot';
  with cfars as (select distinct cfar_nr from afr_ae_history where je_id=p_je_id), states as (
   select h.* from cfars c cross join lateral (
    select h.* from afr_ae_history h join afr_syncs s on s.id=h.sync_id
    where h.cfar_nr=c.cfar_nr and s.status='succeeded' and s.source_date::timestamptz::date<=p_period_end
    order by h.valid_from desc,h.history_id desc limit 1) h)
  select coalesce(jsonb_agg(jsonb_build_object('cfar_nr',cfar_nr::text,'history_id',history_id,'anst_kl',anst_kl,'ae_typ',ae_typ) order by cfar_nr),'[]') into rows
   from states where je_id=p_je_id and in_source and ae_stat=1;
 end if;
 return jsonb_build_object('basis',basis,'sync_id',latest_sync,'establishments',rows);
end $function$;
CREATE OR REPLACE FUNCTION public.company_data_coverage()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '120s'
 SET enable_nestloop TO 'off'
 SET enable_mergejoin TO 'off'
AS $function$
 with ids as (select je_id from afr_je_current where in_source and lan_sate='25'
 union select je_id from afr_ae_current where in_source and ae_stat=1 and lan='25'), establishments as (
 select a.je_id,count(*) n from afr_ae_current a join ids i using(je_id) where a.in_source and a.ae_stat=1 group by a.je_id),
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
$function$;
CREATE OR REPLACE FUNCTION public.company_data_scope(p_after uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 1000)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '120s'
 SET enable_nestloop TO 'on'
 SET enable_mergejoin TO 'on'
AS $function$
declare sid uuid; result jsonb;
begin
 select id into sid from afr_syncs where status='succeeded' order by source_date::timestamptz desc,created_at desc limit 1;
 if sid is null then raise exception 'No published AFR source'; end if;
 if not exists(select 1 from company_account_scope_state where sync_id=sid) then
  perform pg_advisory_xact_lock(hashtext('company-account-scope'));
  if not exists(select 1 from company_account_scope_state where sync_id=sid) then
   delete from company_account_scope_members;
   insert into company_account_scope_members(je_id)
    select je_id from afr_je_current where in_source and lan_sate='25'
    union select je_id from afr_ae_current where in_source and ae_stat=1 and lan='25';
   insert into company_account_scope_state(singleton,sync_id) values(true,sid)
    on conflict(singleton) do update set sync_id=excluded.sync_id,refreshed_at=now();
  end if;
 end if;
 with page as materialized(select je_id from company_account_scope_members where p_after is null or je_id>p_after order by je_id limit least(greatest(p_limit,1),2000)),
 records as (select i.je_id,i.org_nr from page p join afr_je_ident i using(je_id))
 select coalesce(jsonb_agg(to_jsonb(records) order by je_id),'[]') into result from records;
 return result;
end $function$;
delete from public.company_account_scope_state;
-- Re-evaluate previously imported structure without deleting accounts/documents.
update public.company_account_candidates set status='pending' where status='imported';
commit;
