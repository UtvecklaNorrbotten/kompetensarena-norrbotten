-- Applied 2026-11-13. Reparse only new/parser-changed reports; recompute
-- current-structure estimates only for companies with relevant AE changes.
create or replace function public.company_accounts_prepare(p_parser_version text)
returns jsonb language plpgsql security definer set search_path=public set statement_timeout='120s' as $$
declare sid uuid; n int; first_source date;
begin
 select id into sid from afr_syncs where status='succeeded' order by source_date::timestamptz desc,created_at desc limit 1;
 select min(source_date::timestamptz::date) into first_source from afr_syncs where status='succeeded';
 update company_account_candidates c set status='pending'
 where (c.status='quarantined' and c.error_code<>'same_week_multiple_reports' and c.checked_parser_version is distinct from p_parser_version)
 or (c.status='imported' and exists(select 1 from company_accounts_latest l join company_accounts a on a.id=l.account_id
 left join afr_syncs baseline on baseline.id=a.allocation_sync_id
 where l.je_id=c.je_id and (
  a.parser_version<>p_parser_version or baseline.id is null or
  (a.allocation_sync_id<>sid and a.period_end<first_source and (
    exists(select 1 from afr_ae_history h where h.je_id=a.je_id and h.valid_from>baseline.finalized_at
     and h.change_types && array['ny','återkommen','storlek','status','juridisk_enhet','ej_längre_observerad'])
    or exists(select 1 from afr_ae_history previous join afr_ae_history successor
     on successor.cfar_nr=previous.cfar_nr and successor.valid_from=previous.valid_to
     where previous.je_id=a.je_id and previous.valid_to>baseline.finalized_at
     and 'juridisk_enhet'=any(successor.change_types))
  )))));
 get diagnostics n=row_count;
 return jsonb_build_object('requeued',n);
end $$;
