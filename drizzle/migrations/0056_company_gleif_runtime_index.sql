-- Applied manually 2026-11-17. Not journaled; do not reapply through migration replay.
-- Legal scope lookups must not fetch 47,889 random heap pages from national AFR.
create index if not exists afr_je_legal_scope_idx
 on public.afr_je_current(je_id)
 where jurform is not null and jurform<>'10';
analyze public.afr_je_current;
