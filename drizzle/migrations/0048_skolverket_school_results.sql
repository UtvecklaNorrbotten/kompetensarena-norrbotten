-- Skolverket/SIRIS: sex avgränsade skolresultatindikatorer.
-- Skolenhet lagras som dimension; geo_code är skolkommunen eftersom plattformens
-- geografimodell avsiktligt bara innehåller Riket/län/kommun.

insert into public.indicators (
  id, name, description, unit, styrande_kalla, source_table_id,
  frequency, visibility, is_example
) values
  ('skolverket-ak9-gymnasiebehorighet',
   'Behörighet till gymnasieskolans nationella program',
   'Andel elever i årskurs 9 som är behöriga till yrkesprogram, vilket är den grundläggande behörighetsnivån till gymnasieskolans nationella program. Skolenhetsnivå, samtliga elever.',
   'procent','Skolverket','SIRIS export 5','Årlig','publik',false),
  ('skolverket-grundlaggande-hogskolebehorighet',
   'Grundläggande högskolebehörighet',
   'Andel avgångselever från gymnasieskolans nationella program med grundläggande behörighet till högskola. Skolenhetsnivå.',
   'procent','Skolverket','SIRIS export 88','Årlig','publik',false),
  ('skolverket-gymnasieexamen',
   'Gymnasieexamen',
   'Andel avgångselever från gymnasieskolans nationella program med gymnasieexamen. Skolenhetsnivå.',
   'procent','Skolverket','SIRIS export 88','Årlig','publik',false),
  ('skolverket-genomstromning-3-ar',
   'Gymnasieexamen inom 3 år',
   'Andel elever som efter start i gymnasieskolan har tagit gymnasieexamen inom tre år. Skolenhetsnivå, gymnasieskolan totalt.',
   'procent','Skolverket','SIRIS export 360','Årlig','publik',false),
  ('skolverket-genomstromning-4-ar',
   'Gymnasieexamen inom 4 år',
   'Andel elever som efter start i gymnasieskolan har tagit gymnasieexamen inom fyra år. Skolenhetsnivå, gymnasieskolan totalt.',
   'procent','Skolverket','SIRIS export 405','Årlig','publik',false),
  ('skolverket-genomstromning-5-ar',
   'Gymnasieexamen inom 5 år',
   'Andel elever som efter start i gymnasieskolan har tagit gymnasieexamen inom fem år. Skolenhetsnivå, gymnasieskolan totalt.',
   'procent','Skolverket','SIRIS export 410','Årlig','publik',false)
on conflict (id) do update set
  name=excluded.name, description=excluded.description, unit=excluded.unit,
  styrande_kalla=excluded.styrande_kalla, source_table_id=excluded.source_table_id,
  frequency=excluded.frequency, visibility=excluded.visibility,
  is_example=excluded.is_example;

insert into public.data_sources (
  id, provider, name, source_url, cadence, check_from_day_of_month, active
) values (
  'skolverket-siris','Skolverket','Skolverket – skolresultat (SIRIS)',
  'https://siris.skolverket.se/siris/reports/','monthly',null,true
)
on conflict (id) do update set
  provider=excluded.provider, name=excluded.name, source_url=excluded.source_url,
  cadence=excluded.cadence, active=excluded.active;

insert into public.data_source_state (source_id)
values ('skolverket-siris')
on conflict (source_id) do nothing;

notify pgrst, 'reload schema';
