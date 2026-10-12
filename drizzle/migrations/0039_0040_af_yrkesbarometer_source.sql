-- AF Yrkesbarometern: källa och indikator för separata bedömningsomgångar.
-- Kör i Lovable innan en produktionsimport startas.
-- Lagring via befintliga ETL-batchar och observationer.
insert into public.indicators
 (id, name, description, unit, styrande_kalla, source_table_id, frequency, visibility, is_example)
values
 ('af-yrkesbarometern', 'Yrkesbarometern – rekryteringsläge och prognos',
  'Kategoriska bedömningar per yrke och geografiskt område, versionerade per publiceringsomgång. Samtliga källfält, SSYK-relationer och bedömningsgrund ska bevaras i observationsdimensionerna. Kommunvärden får inte skapas genom härledning.',
  'Bedömning', 'Arbetsförmedlingen Yrkesbarometern', 'yrkesbarometer',
  'Halvårsvis', 'admin', false)
on conflict (id) do update set
 name=excluded.name, description=excluded.description, unit=excluded.unit,
 styrande_kalla=excluded.styrande_kalla, source_table_id=excluded.source_table_id,
 frequency=excluded.frequency;
insert into public.data_sources
 (id, provider, name, source_url, cadence, check_from_day_of_month, active)
values
 ('af-yrkesbarometer', 'Arbetsförmedlingen', 'Yrkesbarometern',
  'https://data.arbetsformedlingen.se/prognoser/', 'semiannual', null, true)
on conflict (id) do update set
 provider=excluded.provider, name=excluded.name, source_url=excluded.source_url,
 cadence=excluded.cadence, active=excluded.active;
insert into public.data_source_state (source_id)
 values ('af-yrkesbarometer')
on conflict (source_id) do nothing;
notify pgrst, 'reload schema';