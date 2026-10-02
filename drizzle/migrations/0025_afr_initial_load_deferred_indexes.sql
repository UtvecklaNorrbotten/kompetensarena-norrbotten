-- Första laddningen: hjälpindex och kopplingskontroller pausas och byggs upp stegvis före finalisering.
create table if not exists public.afr_deferred_ddl (
  ord integer primary key,
  name text not null unique,
  ddl text not null
);
grant all on public.afr_deferred_ddl to service_role;
alter table public.afr_deferred_ddl enable row level security;

insert into public.afr_deferred_ddl (ord, name, ddl) values
 (10, 'afr_je_current_agkat_idx', 'create index if not exists afr_je_current_agkat_idx on public.afr_je_current (ag_kat)'),
 (11, 'afr_je_current_kommun_idx', 'create index if not exists afr_je_current_kommun_idx on public.afr_je_current (kommun_sate)'),
 (12, 'afr_je_current_lan_idx', 'create index if not exists afr_je_current_lan_idx on public.afr_je_current (lan_sate)'),
 (13, 'afr_je_current_sync_idx', 'create index if not exists afr_je_current_sync_idx on public.afr_je_current (sync_id)'),
 (14, 'afr_je_current_primary_sni_idx', 'create index if not exists afr_je_current_primary_sni_idx on public.afr_je_current (primary_sni)'),
 (20, 'afr_je_history_sync_idx', 'create index if not exists afr_je_history_sync_idx on public.afr_je_history (sync_id)'),
 (21, 'afr_je_history_je_idx', 'create index if not exists afr_je_history_je_idx on public.afr_je_history (je_id, valid_from)'),
 (30, 'afr_je_sni_current_kod_idx', 'create index if not exists afr_je_sni_current_kod_idx on public.afr_je_sni_current (naringsgren, rangordning)'),
 (40, 'afr_ae_current_sync_idx', 'create index if not exists afr_ae_current_sync_idx on public.afr_ae_current (sync_id)'),
 (41, 'afr_ae_current_je_idx', 'create index if not exists afr_ae_current_je_idx on public.afr_ae_current (je_id)'),
 (42, 'afr_ae_current_anstkl_idx', 'create index if not exists afr_ae_current_anstkl_idx on public.afr_ae_current (anst_kl)'),
 (43, 'afr_ae_current_kommun_idx', 'create index if not exists afr_ae_current_kommun_idx on public.afr_ae_current (kommun)'),
 (44, 'afr_ae_current_lan_idx', 'create index if not exists afr_ae_current_lan_idx on public.afr_ae_current (lan)'),
 (45, 'afr_ae_current_primary_sni_idx', 'create index if not exists afr_ae_current_primary_sni_idx on public.afr_ae_current (primary_sni)'),
 (50, 'afr_ae_history_sync_idx', 'create index if not exists afr_ae_history_sync_idx on public.afr_ae_history (sync_id)'),
 (51, 'afr_ae_history_cfar_idx', 'create index if not exists afr_ae_history_cfar_idx on public.afr_ae_history (cfar_nr, valid_from)'),
 (60, 'afr_ae_sni_current_kod_idx', 'create index if not exists afr_ae_sni_current_kod_idx on public.afr_ae_sni_current (naringsgren, rangordning)'),
 (70, 'afr_je_current_je_id_fkey', 'alter table public.afr_je_current add constraint afr_je_current_je_id_fkey foreign key (je_id) references public.afr_je_ident(je_id)'),
 (71, 'afr_je_history_je_id_fkey', 'alter table public.afr_je_history add constraint afr_je_history_je_id_fkey foreign key (je_id) references public.afr_je_ident(je_id)'),
 (72, 'afr_je_sni_current_je_id_fkey', 'alter table public.afr_je_sni_current add constraint afr_je_sni_current_je_id_fkey foreign key (je_id) references public.afr_je_current(je_id) on delete cascade'),
 (73, 'afr_ae_current_je_id_fkey', 'alter table public.afr_ae_current add constraint afr_ae_current_je_id_fkey foreign key (je_id) references public.afr_je_ident(je_id)'),
 (74, 'afr_ae_history_je_id_fkey', 'alter table public.afr_ae_history add constraint afr_ae_history_je_id_fkey foreign key (je_id) references public.afr_je_ident(je_id)'),
 (75, 'afr_ae_sni_current_cfar_nr_fkey', 'alter table public.afr_ae_sni_current add constraint afr_ae_sni_current_cfar_nr_fkey foreign key (cfar_nr) references public.afr_ae_current(cfar_nr) on delete cascade')
on conflict (ord) do nothing;

-- Pausa: ta bort hjälpindex och kopplingar (primärnycklar och unika nycklar behålls).
alter table public.afr_je_current drop constraint if exists afr_je_current_je_id_fkey;
alter table public.afr_je_history drop constraint if exists afr_je_history_je_id_fkey;
alter table public.afr_je_sni_current drop constraint if exists afr_je_sni_current_je_id_fkey;
alter table public.afr_ae_current drop constraint if exists afr_ae_current_je_id_fkey;
alter table public.afr_ae_history drop constraint if exists afr_ae_history_je_id_fkey;
alter table public.afr_ae_sni_current drop constraint if exists afr_ae_sni_current_cfar_nr_fkey;
drop index if exists public.afr_je_current_agkat_idx, public.afr_je_current_kommun_idx, public.afr_je_current_lan_idx,
  public.afr_je_current_sync_idx, public.afr_je_current_primary_sni_idx, public.afr_je_history_sync_idx, public.afr_je_history_je_idx,
  public.afr_je_sni_current_kod_idx, public.afr_ae_current_sync_idx, public.afr_ae_current_je_idx, public.afr_ae_current_anstkl_idx,
  public.afr_ae_current_kommun_idx, public.afr_ae_current_lan_idx, public.afr_ae_current_primary_sni_idx, public.afr_ae_history_sync_idx,
  public.afr_ae_history_cfar_idx, public.afr_ae_sni_current_kod_idx;

-- Saknade index/kopplingar: tom lista = allt på plats.
create or replace function public.afr_missing_deferred() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(d.name order by d.ord), array[]::text[]) from afr_deferred_ddl d
  where not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname = d.name)
    and not exists (select 1 from pg_constraint k where k.conname = d.name)
$$;

-- Bygger ett saknat index/koppling per anrop.
create or replace function public.afr_rebuild_deferred() returns jsonb
language plpgsql security definer set search_path = public set statement_timeout = '290s' as $$
declare v_name text; v_ddl text; t0 timestamptz := clock_timestamp(); v_left text[];
begin
  select d.name, d.ddl into v_name, v_ddl from afr_deferred_ddl d where d.name = any(afr_missing_deferred()) order by d.ord limit 1;
  if v_name is not null then execute v_ddl; end if;
  v_left := afr_missing_deferred();
  return jsonb_build_object('built', v_name, 'ms', round(extract(epoch from clock_timestamp() - t0) * 1000),
    'remaining', cardinality(v_left), 'done', cardinality(v_left) = 0);
end $$;
revoke all on function public.afr_missing_deferred() from public, anon, authenticated;
revoke all on function public.afr_rebuild_deferred() from public, anon, authenticated;
grant execute on function public.afr_missing_deferred(), public.afr_rebuild_deferred() to service_role;