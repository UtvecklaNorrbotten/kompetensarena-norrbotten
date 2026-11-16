-- Transactional production check: rebuild the compact scope cache, then roll
-- back every cache change. Source/history/documents are never modified.
begin;
delete from public.company_account_scope_state;
do $$
declare expected bigint; actual bigint;
begin
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
end $$;
rollback;
