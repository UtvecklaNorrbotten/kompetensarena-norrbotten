-- Additive registration only. Uses the existing atomically activated ETL batches.
insert into public.indicators
  (id, name, description, unit, styrande_kalla, source_table_id, frequency, visibility, is_example)
values
  ('mucf-uvas-antal', 'Unga som varken arbetar eller studerar – antal (MUCF)',
   'MUCF:s registerbaserade UVAS-mått. Alla tillgängliga år, riket, län och kommuner; 16–24, 25–29 och 16–29 år. Kön, födelseland och aktivitetskategorier enligt källans tillgängliga kombinationer. Sekretessmarkerade värden bevaras som null med originalmarkering. Från 2023 används CKM; delar ska inte summeras till totaler. Gränspendling till Finland exkluderas från 2015. Måttet är inte identiskt med NEET.',
   'Personer', 'MUCF', 'MUCF UVAS', 'Årlig', 'publik', false),
  ('mucf-uvas-andel', 'Unga som varken arbetar eller studerar – andel (MUCF)',
   'Total UVAS (Master) avser andel av befolkningen. Aktivitetskategorier avser andel av UVAS i motsvarande grupp. Dessa nämnare får inte blandas. Källans publicerade totaler och andelar hämtas separat; ingen summering eller imputation. Sekretessmarkering, CKM från 2023 och ändrad gränspendlaravgränsning 2015 följer med datan.',
   'Procent', 'MUCF', 'MUCF UVAS', 'Årlig', 'publik', false)
on conflict (id) do update set
  name = excluded.name, description = excluded.description, unit = excluded.unit,
  styrande_kalla = excluded.styrande_kalla, source_table_id = excluded.source_table_id,
  frequency = excluded.frequency;

insert into public.data_sources (id, provider, name, source_url, cadence, active)
values ('mucf-uvas', 'MUCF', 'Unga som varken arbetar eller studerar (UVAS)',
 'https://www.mucf.se/rapporter-och-statistik/statistik-om-unga-som-varken-arbetar-eller-studerar',
 'weekly', true)
on conflict (id) do update set
 provider = excluded.provider, name = excluded.name, source_url = excluded.source_url,
 cadence = excluded.cadence, active = excluded.active;
insert into public.data_source_state (source_id)
values ('mucf-uvas') on conflict (source_id) do nothing;
