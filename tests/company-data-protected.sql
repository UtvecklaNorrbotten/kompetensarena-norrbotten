-- Synthetic values only. All writes roll back, including contact overwrites.
begin;
do $$
declare sid uuid; k text; eid text; n bigint; v bigint; c jsonb; p text; h text; item jsonb;
begin
 select id into strict sid from afr_syncs where status='succeeded' order by created_at desc limit 1;
 select i.pe_org_nr,i.je_id::text into strict k,eid from afr_je_ident i join afr_je_current j using(je_id) where j.in_source limit 1;
 select count(*) into n from afr_profile_versions where entity='je' and entity_id=eid;
 p:='{"namn":"Syntetiskt test A","foretagsnamn":null,"postAdress":{},"expImp":"N"}';
 h:=afr_hash(p);
 item:=jsonb_build_object('key',k,'profile_canonical',p,'profile_hash',h,'contact_canonical','{"tel":"syntetisk-1","epost":null}',
 'contact_hash',afr_hash('{"tel":"syntetisk-1","epost":null}'));
 perform afr_profile_store(sid,'je',jsonb_build_array(item));
 perform afr_profile_store(sid,'je',jsonb_build_array(item));
 select count(*) into v from afr_profile_versions where entity='je' and entity_id=eid;
 if v<>n+1 then raise exception 'Idempotency failed'; end if;
 item:=item||jsonb_build_object('contact_canonical','{"tel":"syntetisk-2","epost":null}',
 'contact_hash',afr_hash('{"tel":"syntetisk-2","epost":null}'));
 perform afr_profile_store(sid,'je',jsonb_build_array(item));
 select count(*) into v from afr_profile_versions where entity='je' and entity_id=eid;
 if v<>n+1 then raise exception 'Contact created history'; end if;
 select contact into c from afr_profile_current where entity='je' and entity_id=eid;
 if c->>'tel'<>'syntetisk-2' then raise exception 'Latest contact missing'; end if;
 p:='{"namn":"Syntetiskt test B","foretagsnamn":null,"postAdress":{},"expImp":"J"}';
 item:=item||jsonb_build_object('profile_canonical',p,'profile_hash',afr_hash(p));
 perform afr_profile_store(sid,'je',jsonb_build_array(item));
 if not exists(select 1 from afr_profile_versions where entity='je' and entity_id=eid and change_types @> array['namnbyte','tillkomst_export_importmarkering_i_registret']) then raise exception 'Change classification failed'; end if;
 if has_table_privilege('anon','afr_profile_versions','select') or has_table_privilege('anon','company_accounts','select') then raise exception 'Anonymous access'; end if;
 if has_function_privilege('anon','afr_profile_store(uuid,text,jsonb)','execute') then raise exception 'Public write RPC'; end if;
 if exists(select 1 from storage.buckets where id='company-source-documents' and public) then raise exception 'Public document bucket'; end if;
end $$;
rollback;
