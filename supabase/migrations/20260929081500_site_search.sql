-- Publikt sökindex. Lägg aldrig råa enkätsvar eller personuppgifter här.
create table if not exists public.search_index (
  id text primary key,
  kind text not null,
  title text not null,
  description text,
  url text not null,
  search_vector tsvector generated always as
    (to_tsvector('swedish'::regconfig, coalesce(title, '') || ' ' || coalesce(description, ''))) stored,
  updated_at timestamptz not null default now(),
  constraint search_index_url_internal check (url like '/%' and url not like '//%')
);
create index if not exists search_index_vector_idx on public.search_index using gin (search_vector);
alter table public.search_index enable row level security;
create policy "Public can search published entries" on public.search_index for select to anon, authenticated using (true);
revoke all on public.search_index from anon, authenticated;
grant select on public.search_index to anon, authenticated;

create or replace function public.search_site(query_text text)
returns table(kind text, title text, description text, url text)
language sql stable security invoker set search_path = public
as $$
  select s.kind, s.title, s.description, s.url
  from public.search_index s
  where length(btrim(query_text)) between 2 and 100
    and s.search_vector @@ websearch_to_tsquery('swedish'::regconfig, query_text)
  order by ts_rank_cd(s.search_vector, websearch_to_tsquery('swedish'::regconfig, query_text)) desc, s.title
  limit 20;
$$;
revoke all on function public.search_site(text) from public;
grant execute on function public.search_site(text) to anon, authenticated;

insert into public.search_index (id, kind, title, description, url) values
('page:home','Sida','Startsida','Kunskap om kompetensförsörjning i Norrbotten','/'),
('page:om','Sida','Om Kompetensarena','Uppdrag, samverkan och kontakt','/om'),
('page:statistik','Sida','Statistik','Indikatorer och metadata','/statistik'),
('page:downloads','Sida','Ladda ned data','Data och metod','/ladda-ned-data'),
('area:yrken','Område','Yrken','Yrken och kompetensbehov','/omraden/yrken'),
('area:branscher','Område','Branscher','Branscher och arbetsgivarnas behov','/omraden/branscher'),
('area:lan-kommun','Område','Län och kommun','Geografi och befolkningsutveckling','/omraden/lan-kommun'),
('area:utbildning','Område','Utbildning','Utbildningsutbud och behov','/omraden/utbildning'),
('area:kompetenser','Område','Kompetenser','Kompetenser som efterfrågas','/omraden/kompetenser')
on conflict (id) do update set title=excluded.title, description=excluded.description, url=excluded.url, updated_at=now();

-- Publicerade indikatorer är sökbara. Enskilda observationer indexeras inte.
create or replace function public.sync_indicator_search()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    delete from public.search_index where id = 'indicator:' || old.id::text;
    return old;
  end if;
  insert into public.search_index (id, kind, title, description, url)
    values ('indicator:' || new.id::text, 'Indikator', new.name, new.description, '/statistik')
  on conflict (id) do update set title=excluded.title, description=excluded.description, updated_at=now();
  return new;
end;
$$;
drop trigger if exists sync_indicator_search_trigger on public.indicators;
create trigger sync_indicator_search_trigger after insert or update or delete on public.indicators
for each row execute function public.sync_indicator_search();
insert into public.search_index (id, kind, title, description, url)
select 'indicator:' || id::text, 'Indikator', name, description, '/statistik'
from public.indicators
on conflict (id) do update set title=excluded.title, description=excluded.description, updated_at=now();
revoke all on function public.sync_indicator_search() from public;

-- Kommuner/regioner synkas från geographies. Ytterligare SSYK- och SNI-register
-- kopplas in först när deras källtabeller och publika detaljsidor är fastställda.
create or replace function public.sync_geography_search()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    delete from public.search_index where id = 'geo:' || old.code;
    return old;
  end if;
  insert into public.search_index (id, kind, title, description, url)
    values ('geo:' || new.code, 'Geografi', new.name, new.code, '/omraden/lan-kommun')
  on conflict (id) do update set title=excluded.title, description=excluded.description, updated_at=now();
  return new;
end;
$$;
drop trigger if exists sync_geography_search_trigger on public.geographies;
create trigger sync_geography_search_trigger after insert or update or delete on public.geographies
for each row execute function public.sync_geography_search();
insert into public.search_index (id, kind, title, description, url)
select 'geo:' || code, 'Geografi', name, code, '/omraden/lan-kommun'
from public.geographies
on conflict (id) do update set title=excluded.title, description=excluded.description, updated_at=now();
revoke all on function public.sync_geography_search() from public;
