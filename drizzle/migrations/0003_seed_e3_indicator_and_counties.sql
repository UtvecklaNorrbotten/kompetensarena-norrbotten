-- Första riktiga indikatorn: E3 / SCB TAB6929.
-- Första versionen publicerar län. Riket och kommuner läggs till senare.

insert into public.geographies (code, name, level) values
  ('01', 'Stockholms län', 'län'),
  ('03', 'Uppsala län', 'län'),
  ('04', 'Södermanlands län', 'län'),
  ('05', 'Östergötlands län', 'län'),
  ('06', 'Jönköpings län', 'län'),
  ('07', 'Kronobergs län', 'län'),
  ('08', 'Kalmar län', 'län'),
  ('09', 'Gotlands län', 'län'),
  ('10', 'Blekinge län', 'län'),
  ('12', 'Skåne län', 'län'),
  ('13', 'Hallands län', 'län'),
  ('14', 'Västra Götalands län', 'län'),
  ('17', 'Värmlands län', 'län'),
  ('18', 'Örebro län', 'län'),
  ('19', 'Västmanlands län', 'län'),
  ('20', 'Dalarnas län', 'län'),
  ('21', 'Gävleborgs län', 'län'),
  ('22', 'Västernorrlands län', 'län'),
  ('23', 'Jämtlands län', 'län'),
  ('24', 'Västerbottens län', 'län'),
  ('25', 'Norrbottens län', 'län')
on conflict (code) do update set
  name = excluded.name,
  level = excluded.level;

insert into public.indicators (
  id,
  name,
  description,
  unit,
  styrande_kalla,
  source_table_id,
  frequency,
  visibility,
  is_example
) values (
  'e3-matchning-utbildning',
  'Matchning mellan utbildning och yrke (E3)',
  'SCB:s indikator E3 för matchning mellan utbildning och yrke. Första versionen omfattar län.',
  'Varierar per tabellinnehåll',
  'TAB6929',
  'TAB6929',
  'Årlig',
  'publik',
  false
)
on conflict (id) do update set
  name = excluded.name,
  description = excluded.description,
  unit = excluded.unit,
  styrande_kalla = excluded.styrande_kalla,
  source_table_id = excluded.source_table_id,
  frequency = excluded.frequency,
  visibility = excluded.visibility,
  is_example = excluded.is_example;
