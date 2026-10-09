-- BAS använder befintliga geographies och ETL-batchfunktioner.
-- Ingen ändring av publiceringslogik eller befintliga indikatorer.
insert into public.indicators
  (id, name, description, unit, styrande_kalla, source_table_id, frequency, visibility, is_example)
values
  ('bas-sysselsatta-bransch', 'Sysselsatta efter bransch (BAS)',
   'Preliminär månadsstatistik från 2020. Riket, 21 län och 290 kommuner; 15 breda branschgrupper, totalt och uppgift saknas. Kön: kvinnor, män och totalt. 15–74 år, födelseregion totalt. Arbetsställets och bostadens belägenhet hålls isär. Antal personer, inklusive företagare.',
   'Personer', 'TAB3784', 'TAB3784', 'Månatlig', 'publik', false),
  ('bas-sysselsatta-sektor', 'Sysselsatta efter sektor (BAS)',
   'Preliminär månadsstatistik från 2020. Riket, 21 län och 290 kommuner; alla åtta sektorkategorier inklusive totalt. Kön: kvinnor, män och totalt. 15–74 år, födelseregion totalt. Arbetsställets och bostadens belägenhet hålls isär. Sektortotaler överlappar; ingen korsning med bransch.',
   'Personer', 'TAB2597', 'TAB2597', 'Månatlig', 'publik', false)
on conflict (id) do update set
  name = excluded.name, description = excluded.description, unit = excluded.unit,
  styrande_kalla = excluded.styrande_kalla, source_table_id = excluded.source_table_id,
  frequency = excluded.frequency;

insert into public.data_sources
  (id, provider, name, source_url, cadence, check_from_day_of_month, active)
values
  ('scb-bas-industry', 'SCB', 'BAS – sysselsatta per bransch',
   'https://statistikdatabasen.scb.se/api/v2/tables/TAB3784', 'monthly', 22, true),
  ('scb-bas-sector', 'SCB', 'BAS – sysselsatta per sektor',
   'https://statistikdatabasen.scb.se/api/v2/tables/TAB2597', 'monthly', 22, true)
on conflict (id) do update set
  provider = excluded.provider, name = excluded.name, source_url = excluded.source_url,
  cadence = excluded.cadence, check_from_day_of_month = excluded.check_from_day_of_month,
  active = excluded.active;

insert into public.data_source_state (source_id)
values ('scb-bas-industry'), ('scb-bas-sector')
on conflict (source_id) do nothing;

notify pgrst, 'reload schema';
