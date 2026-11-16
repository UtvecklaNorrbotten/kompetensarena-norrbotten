-- Read-only aggregate checks against actual AFR history/current structure.
-- Interpret pending separately: a newer candidate must not count as verified.
set enable_nestloop=off;
set enable_mergejoin=off;
with latest as materialized (
 select a.* from public.company_accounts_latest l
 join public.company_accounts a on a.id=l.account_id
 join public.company_account_scope_members s on s.je_id=l.je_id
 join public.company_account_candidates c on c.je_id=l.je_id
 where c.status='imported' and c.package_sha256=a.package_sha256
), first_source as (
 select min(source_date::timestamptz::date) as day from public.afr_syncs where status='succeeded'
), expected as materialized (
 select a.id as account_id,e.cfar_nr from latest a cross join first_source f
 join public.afr_ae_current e on e.je_id=a.je_id
 where a.period_end<f.day and e.in_source and e.ae_stat=1
 union all
 select a.id,(e->>'cfar_nr')::bigint from latest a cross join first_source f
 cross join lateral jsonb_array_elements(public.company_account_structure(a.je_id,a.period_end)->'establishments') e
 where a.period_end>=f.day
), actual as materialized (
 select x.account_id,x.cfar_nr from public.company_account_allocations x
 join latest a on a.id=x.account_id
)
select
 (select count(*) from expected e full join actual x using(account_id,cfar_nr)
  where e.account_id is null or x.account_id is null) as denominator_differences,
 (select count(*) from public.company_account_allocations x join latest a on a.id=x.account_id
  left join public.afr_ae_history h on h.history_id=x.structure_history_id
  where h.history_id is null or not h.in_source or h.ae_stat<>1 or h.je_id<>a.je_id or h.cfar_nr<>x.cfar_nr
 ) as invalid_history_or_inactive_allocations,
 (select count(*) from latest where package_sha256 !~ '^[0-9a-f]{64}$'
  or document_sha256 !~ '^[0-9a-f]{64}$' or provenance='{}'::jsonb) as invalid_checksums_or_provenance,
 (select count(*) from public.company_account_allocations x join latest a on a.id=x.account_id
  join public.afr_ae_history h on h.history_id=x.structure_history_id where h.lan<>'25'
 ) as allocated_establishments_outside_norrbotten;
