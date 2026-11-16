-- Applied manually 2026-11-16; not journaled for automatic replay.
-- Same scope predicate as 0050. No documents/history/candidates are reset.
begin;
set local lock_timeout='2s';
create index if not exists afr_je_company_scope_25_idx
 on public.afr_je_current(je_id) where in_source and lan_sate='25';
create index if not exists afr_ae_company_scope_25_idx
 on public.afr_ae_current(je_id) where in_source and ae_stat=1 and lan='25';
-- The default 20% vacuum threshold leaves sparse daily changes across too
-- many heap pages before visibility can be restored for index-only scans.
alter table public.afr_je_current set
 (autovacuum_vacuum_scale_factor=0.01, autovacuum_analyze_scale_factor=0.01);
alter table public.afr_ae_current set
 (autovacuum_vacuum_scale_factor=0.01, autovacuum_analyze_scale_factor=0.01);
commit;
-- Run separately, outside a transaction, after initial application:
-- vacuum (analyze) public.afr_je_current;
-- vacuum (analyze) public.afr_ae_current;
