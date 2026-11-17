-- Apply once manually; not in the automatic Drizzle journal.
begin;
create table public.company_account_supplements (
 je_id uuid not null references public.afr_je_ident(je_id),
 package_sha256 text not null check(package_sha256 ~ '^[a-f0-9]{64}$'),
 parser_version text not null,
 document_sha256 text check(document_sha256 is null or document_sha256 ~ '^[a-f0-9]{64}$'),
 origin text not null check(origin in ('bulk','api')),
 quality_status text not null check(quality_status in ('with_reservation','source_only')),
 reason text not null, period_end date,
 document jsonb, source jsonb not null,
 created_at timestamptz not null default now(),
 primary key(je_id,package_sha256,parser_version),
 check((quality_status='with_reservation')=(document is not null))
);
create table public.company_account_api_checks (
 je_id uuid primary key references public.afr_je_ident(je_id),
 outcome text not null, documents_count integer not null check(documents_count>=0),
 checked_at timestamptz not null default now(), retry_after timestamptz not null
);
do $$ declare t text; begin
 foreach t in array array['company_account_supplements','company_account_api_checks'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 execute format('grant all on public.%I to service_role',t);
 execute format('create policy admin_read on public.%I for select to authenticated using(public.has_role(auth.uid(),''admin''))',t);
 end loop;
end $$;
create function public.company_account_supplement_queue(p_mode text,p_after uuid default null)
returns jsonb language sql security definer set search_path=public set statement_timeout='30s' as $$
 select coalesce(jsonb_agg(to_jsonb(q) order by q.je_id),'[]') from (
 select s.je_id,i.org_nr,c.period_end,c.package_sha256,c.archive_etag
 from company_account_scope_members s join afr_je_ident i using(je_id)
 join afr_je_current j using(je_id)
 left join company_account_candidates c using(je_id)
 left join company_account_api_checks a using(je_id)
 where j.jurform in ('41','42','49') and (p_after is null or s.je_id>p_after)
 and ((p_mode='bulk' and c.status='quarantined' and c.package_sha256 is not null
 and not exists(select 1 from company_account_supplements v where v.je_id=s.je_id and v.package_sha256=c.package_sha256 and v.parser_version='bv-supplement-1'))
 or (p_mode='api' and c.je_id is null and (a.je_id is null or a.retry_after<=now())))
 order by s.je_id limit 100) q;
$$;
create function public.company_account_supplement_store(p_je_id uuid,p_result jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c company_account_candidates%rowtype; sh text:=p_result->>'package_sha256';
 origin text:=p_result->>'origin'; doc jsonb:=nullif(p_result->'document','null'::jsonb);
begin
 if not exists(select 1 from company_account_scope_members s join afr_je_current j using(je_id)
 where s.je_id=p_je_id and j.jurform in ('41','42','49')) then raise exception 'Company outside AB scope'; end if;
 select * into c from company_account_candidates where je_id=p_je_id for update;
 if origin='bulk' then
   if c.je_id is null or c.status<>'quarantined' or c.package_sha256 is distinct from sh
     or c.archive_etag is distinct from p_result->'source'->>'archive_etag'
     or c.period_end is distinct from (p_result->>'period_end')::date then raise exception 'Candidate changed'; end if;
 elsif origin='api' then
   if c.je_id is not null then raise exception 'Bulk candidate appeared'; end if;
 else raise exception 'Invalid origin'; end if;
 if sh is not null then
   if not exists(select 1 from storage.objects where bucket_id='company-source-documents' and name='accounts/'||sh||'.zip') then raise exception 'Missing saved source'; end if;
   if doc is not null and (doc->>'period_end' is distinct from p_result->>'period_end'
     or doc->>'scope'<>'company' or doc->>'unit'<>'currency_units'
     or jsonb_typeof(doc->'metrics')<>'object') then raise exception 'Invalid reserved document'; end if;
   insert into company_account_supplements(je_id,package_sha256,parser_version,document_sha256,origin,quality_status,reason,period_end,document,source)
   values(p_je_id,sh,'bv-supplement-1',p_result->>'document_sha256',origin,p_result->>'quality_status',p_result->>'reason',
      (p_result->>'period_end')::date,doc,(p_result->'source')||jsonb_build_object('storage_path','accounts/'||sh||'.zip')||
       case when origin='bulk' then jsonb_build_object('archive_key',c.archive_key,'member_name',c.member_name) else '{}'::jsonb end)
   on conflict(je_id,package_sha256,parser_version) do nothing;
 end if;
 if origin='api' then
   insert into company_account_api_checks(je_id,outcome,documents_count,retry_after)
   values(p_je_id,p_result->>'reason',(p_result->>'documents_count')::integer,
     now()+case when p_result->>'reason'='api_error' then interval '1 day' else interval '30 days' end)
   on conflict(je_id) do update set outcome=excluded.outcome,documents_count=excluded.documents_count,
     checked_at=now(),retry_after=excluded.retry_after;
 end if;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.company_account_supplement_queue(text,uuid),public.company_account_supplement_store(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.company_account_supplement_queue(text,uuid),public.company_account_supplement_store(uuid,jsonb) to service_role;
commit;
