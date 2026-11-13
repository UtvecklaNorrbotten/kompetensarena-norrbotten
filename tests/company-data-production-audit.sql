-- Read-only production validation. Aggregates only; no identities or contacts.
with latest as (
 select a.* from public.company_accounts_latest l
 join public.company_accounts a on a.id=l.account_id
), grouped as (
 select x.account_id,sum(x.weight) weights,sum(x.estimated_net_sales) estimated,
 count(*) filter(where x.estimated_net_sales is not null) populated,
 bool_and(x.is_estimate) estimates
 from public.company_account_allocations x join latest a on a.id=x.account_id
 group by x.account_id
)
select
 (select count(*) from latest) saved_companies,
 (select count(*) from latest a where not exists (
   select 1 from storage.objects o where o.bucket_id='company-source-documents' and o.name=a.storage_path)) missing_source_packages,
 (select count(*) from grouped where weights<>1) invalid_weight_sums,
 (select count(*) from grouped g join latest a on a.id=g.account_id
   where (a.net_sales is null and g.populated<>0)
      or (a.net_sales is not null and g.estimated is distinct from a.net_sales)) invalid_sales_sums,
 (select count(*) from grouped where not estimates) unmarked_estimates,
 (select count(*) from latest where scope<>'company') noncompany_accounts,
 (select count(*) from latest where
   operating_margin is distinct from 100*operating_profit/nullif(net_sales,0)
   or equity_ratio is distinct from 100*equity/nullif(total_assets,0)) invalid_ratios,
 (select count(*) from public.afr_profile_current) current_profiles,
 (select count(*) from public.afr_profile_versions) profile_versions,
 (select count(*) from public.afr_profile_releases) completed_profile_releases;

-- Every sensitive table must have RLS enabled. Empty result is expected.
select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public'
 and (c.relname like 'afr_profile_%' or c.relname like 'company_account%')
 and c.relkind='r' and not c.relrowsecurity;

select id,public from storage.buckets where id='company-source-documents';
