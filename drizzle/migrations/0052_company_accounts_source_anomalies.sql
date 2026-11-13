-- Aggregate review flags; never silently correct signs or period lengths.
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
 'source_anomalies',jsonb_build_object(
 'negative_total_assets',(select count(*) from latest where total_assets<0),
 'negative_net_sales',(select count(*) from latest where net_sales<0),
 'negative_average_employees',(select count(*) from latest where average_employees<0),
 'periods_other_than_twelve_months',(select count(*) from latest where period_end<>(period_start+interval '1 year'-interval '1 day')::date)),
 'weight_sum_errors',(select count(*) from (select account_id from alloc group by account_id having sum(weight)<>1) q),
 'archives_scanned',(select count(*) from company_account_archives))
$function$;
