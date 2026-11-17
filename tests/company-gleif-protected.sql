-- Reversible production contract test; no synthetic data persists.
begin;
do $$
declare j uuid; text_value text:='{"entities":[],"status":"not_found"}'; sh text; r jsonb; n integer;
begin
 select s.je_id into strict j from company_account_scope_members s join afr_je_current c using(je_id)
 where c.jurform is not null and c.jurform<>'10' order by s.je_id limit 1;
 sh:=encode(extensions.digest(convert_to(text_value,'UTF8'),'sha256'),'hex');
 r:=jsonb_build_array(jsonb_build_object('je_id',j,'canonical_payload',text_value,'payload_sha256',sh,'source',jsonb_build_object('test','synthetic','afr_sync_id',(select sync_id from company_account_scope_state))));
 perform company_gleif_store('identity',r); perform company_gleif_store('identity',r);
 select count(*) into n from company_gleif_versions where je_id=j and stage='identity' and payload_sha256=sh;
 if n<>1 then raise exception 'Idempotence failure'; end if;
 if has_table_privilege('anon','company_gleif_versions','select')
 or has_function_privilege('authenticated','company_gleif_store(text,jsonb)','execute')
 or has_function_privilege('anon','company_gleif_scope(uuid)','execute') then raise exception 'Permission failure'; end if;
 if (select count(*) from pg_class where oid in ('company_gleif_versions'::regclass,'company_gleif_current'::regclass) and relrowsecurity)<>2 then raise exception 'RLS failure'; end if;
 begin
  perform company_gleif_store('identity',jsonb_build_array(jsonb_build_object('je_id',j,'canonical_payload',text_value,'payload_sha256',repeat('0',64),'source',jsonb_build_object('afr_sync_id',(select sync_id from company_account_scope_state)))));
  raise exception using errcode='XX001',message='Checksum accepted unexpectedly';
 exception when sqlstate 'P0001' then null;
 end;
end $$;
rollback;
