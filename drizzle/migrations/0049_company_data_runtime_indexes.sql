-- Applied 2026-11-13. A compact scope cache contains only internal JE keys.
-- It is rebuilt once per published AFR sync, not once per page of 1,000 keys.
begin;
create table public.company_account_scope_members (
 je_id uuid primary key references public.afr_je_ident(je_id)
);
create table public.company_account_scope_state (
 singleton boolean primary key default true check(singleton),
 sync_id uuid not null references public.afr_syncs(id),
 refreshed_at timestamptz not null default now()
);
alter table public.company_account_scope_members enable row level security;
alter table public.company_account_scope_state enable row level security;
revoke all on public.company_account_scope_members,public.company_account_scope_state from public,anon,authenticated;
grant select on public.company_account_scope_members,public.company_account_scope_state to authenticated;
grant all on public.company_account_scope_members,public.company_account_scope_state to service_role;
create policy admin_read on public.company_account_scope_members for select to authenticated using(public.has_role(auth.uid(),'admin'));
create policy admin_read on public.company_account_scope_state for select to authenticated using(public.has_role(auth.uid(),'admin'));
create or replace function public.company_data_scope(p_after uuid default null,p_limit int default 1000)
returns jsonb language plpgsql volatile security definer set search_path=public set statement_timeout='120s'
set enable_nestloop='on' set enable_mergejoin='on' as $$
declare sid uuid; result jsonb;
begin
 select id into sid from afr_syncs where status='succeeded' order by source_date::timestamptz desc,created_at desc limit 1;
 if sid is null then raise exception 'No published AFR source'; end if;
 if not exists(select 1 from company_account_scope_state where sync_id=sid) then
  perform pg_advisory_xact_lock(hashtext('company-account-scope'));
  if not exists(select 1 from company_account_scope_state where sync_id=sid) then
   delete from company_account_scope_members;
   insert into company_account_scope_members(je_id)
    select je_id from afr_je_current where in_source and lan_sate='25'
    union select je_id from afr_ae_current where in_source and lan='25';
   insert into company_account_scope_state(singleton,sync_id) values(true,sid)
    on conflict(singleton) do update set sync_id=excluded.sync_id,refreshed_at=now();
  end if;
 end if;
 with page as materialized(select je_id from company_account_scope_members where p_after is null or je_id>p_after order by je_id limit least(greatest(p_limit,1),2000)),
 records as (select i.je_id,i.org_nr from page p join afr_je_ident i using(je_id))
 select coalesce(jsonb_agg(to_jsonb(records) order by je_id),'[]') into result from records;
 return result;
end $$;
-- Core publication must not walk nationwide UUID indexes in a merge join for
-- the bounded delta. Hash joins with a bounded memory allowance avoid random IO.
alter function public.afr_finalize_sync_apply(uuid,jsonb) set enable_mergejoin='off';
alter function public.afr_finalize_sync_apply(uuid,jsonb) set enable_nestloop='off';
alter function public.afr_finalize_sync_apply(uuid,jsonb) set work_mem='64MB';
commit;
