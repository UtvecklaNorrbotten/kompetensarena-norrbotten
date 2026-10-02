-- Finalisering kräver att alla pausade index/kopplingar finns och är validerade.
create or replace function public.afr_assert_deferred_ready() returns void
language plpgsql stable security definer set search_path = public as $$
declare v_missing text[] := afr_missing_deferred(); v_invalid text;
begin
  if cardinality(v_missing) > 0 then
    raise exception 'Index/kopplingar saknas: %', array_to_string(v_missing, ', ') using errcode = 'invalid_parameter_value';
  end if;
  select string_agg(c.relname, ', ') into v_invalid from pg_index i join pg_class c on c.oid = i.indexrelid
    join afr_deferred_ddl d on d.name = c.relname where not i.indisvalid or not i.indisready;
  if v_invalid is not null then raise exception 'Ogiltiga index: %', v_invalid using errcode = 'invalid_parameter_value'; end if;
  select string_agg(k.conname, ', ') into v_invalid from pg_constraint k join afr_deferred_ddl d on d.name = k.conname where not k.convalidated;
  if v_invalid is not null then raise exception 'Ovaliderade kopplingar: %', v_invalid using errcode = 'invalid_parameter_value'; end if;
end $$;
revoke all on function public.afr_assert_deferred_ready() from public, anon, authenticated;
grant execute on function public.afr_assert_deferred_ready() to service_role;

-- Spärr i afr_syncs: en synk kan bara bli succeeded om alla index/kopplingar är på plats.
create or replace function public.afr_syncs_guard_success() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'succeeded' and old.status is distinct from 'succeeded' then
    perform afr_assert_deferred_ready();
  end if;
  return new;
end $$;
drop trigger if exists afr_syncs_guard_success on public.afr_syncs;
create trigger afr_syncs_guard_success before update of status on public.afr_syncs
  for each row execute function public.afr_syncs_guard_success();

-- Nya synkar (daglig) får inte starta medan index saknas.
create or replace function public.afr_syncs_guard_start() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.mode <> 'initial' then perform afr_assert_deferred_ready(); end if;
  return new;
end $$;
drop trigger if exists afr_syncs_guard_start on public.afr_syncs;
create trigger afr_syncs_guard_start before insert on public.afr_syncs
  for each row execute function public.afr_syncs_guard_start();