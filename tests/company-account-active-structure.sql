-- Read-only assertions against real source status; 1900 is a synthetic
-- period used only to force the documented current-structure fallback.
begin;
do $$ declare j uuid; s jsonb; begin
 select je_id into strict j from afr_ae_current where in_source and ae_stat=9 and lan='25' limit 1;
 s:=company_account_structure(j,date '1900-01-01');
 if exists(select 1 from jsonb_array_elements(s->'establishments') e join afr_ae_current a on a.cfar_nr=(e->>'cfar_nr')::bigint where a.ae_stat<>1) then
  raise exception 'Inactive establishment entered turnover denominator'; end if;
 if exists(select 1 from jsonb_array_elements(s->'establishments') e where not(e ? 'ae_typ')) then
  raise exception 'Establishment type provenance missing'; end if;
end $$;
rollback;
