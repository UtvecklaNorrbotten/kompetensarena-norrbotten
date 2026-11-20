-- Transactional production check: rebuild the compact scope cache, then roll
-- back every cache change. Source/history/documents are never modified.
-- safeupdate is enforced in the real API session; verify that path in Actions.
begin;
delete from public.company_account_scope_state where singleton;
do $$
declare expected bigint; actual bigint; versions bigint; accounts bigint;
begin
 select count(*) into versions from public.company_gleif_versions;
 select count(*) into accounts from public.company_accounts;
 -- GLEIF must recover first, without depending on a preceding accounts job.
 if jsonb_array_length(public.company_gleif_scope(null))=0 then raise exception 'Empty recovered GLEIF scope'; end if;
 select count(*) into expected from (
  select je_id from public.afr_je_current where in_source and lan_sate='25'
  union select je_id from public.afr_ae_current where in_source and ae_stat=1 and lan='25'
 ) s;
 if expected=0 then raise exception 'Empty expected scope'; end if;
 if jsonb_array_length(public.company_data_scope())<>least(expected,1000) then
  raise exception 'Unexpected first scope page';
 end if;
 select count(*) into actual from public.company_account_scope_members;
 if actual<>expected then raise exception 'Rebuilt scope count mismatch'; end if;
 if exists(
  (select je_id from public.company_account_scope_members except
   (select je_id from public.afr_je_current where in_source and lan_sate='25'
    union select je_id from public.afr_ae_current where in_source and ae_stat=1 and lan='25'))
 ) then raise exception 'Rebuilt scope membership mismatch'; end if;
 if (select count(*) from public.company_gleif_versions)<>versions or (select count(*) from public.company_accounts)<>accounts then
  raise exception 'Scope refresh changed verified data'; end if;
 if has_function_privilege('anon','public.company_data_refresh_scope()','execute') or has_function_privilege('authenticated','public.company_data_refresh_scope()','execute') then raise exception 'Refresh permission leak'; end if;
 -- A second refresh must keep the existing membership and publication timestamp.
 perform public.company_data_refresh_scope();
 if (select count(*) from public.company_account_scope_members)<>expected then raise exception 'Non-idempotent refresh'; end if;
end $$;
rollback;
