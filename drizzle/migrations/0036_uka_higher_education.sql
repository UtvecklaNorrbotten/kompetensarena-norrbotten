-- UKÄ: nationell högskolestatistik för Kompetensarena.
-- Lärosäte lagras som dimension; geo_code är Riket ('00') eftersom lärosäten inte är geografier.

insert into public.data_sources (
  id, provider, name, source_url, cadence, check_from_day_of_month, active
) values (
  'uka-hogskolan-i-siffror',
  'UKÄ',
  'Högskolan i siffror',
  'https://www.uka.se/statistik-och-analys/hogskolan-i-siffror',
  'weekly',
  null,
  true
)
on conflict (id) do update set
  provider = excluded.provider,
  name = excluded.name,
  source_url = excluded.source_url,
  cadence = excluded.cadence,
  active = excluded.active;

insert into public.data_source_state (source_id)
values ('uka-hogskolan-i-siffror')
on conflict (source_id) do nothing;

insert into public.indicators (
  id, name, description, unit, styrande_kalla, source_table_id,
  frequency, visibility, is_example
) values
  (
    'uka-forstahandssokande-yrkesprogram',
    'Förstahandssökande till yrkesexamensprogram',
    'Behöriga förstahandssökande till program som leder till yrkesexamen, efter lärosäte, program och kön.',
    'antal', 'UKÄ', '13', 'Terminsvis', 'publik', false
  ),
  (
    'uka-nyborjare-yrkesprogram',
    'Nybörjare på yrkesexamensprogram',
    'Nybörjare på yrkesexamensprogram efter lärosäte, program och kön.',
    'antal', 'UKÄ', '31', 'Terminsvis', 'publik', false
  ),
  (
    'uka-hst',
    'Helårsstudenter',
    'Helårsstudenter efter lärosäte, studieform, ämnesområde, ämnesdelområde, ämnesgrupp och kön.',
    'HST', 'UKÄ', '33', 'Årlig', 'publik', false
  ),
  (
    'uka-antagna-yrkesprogram',
    'Antagna till yrkesexamensprogram',
    'Antagna till program som leder till yrkesexamen, efter lärosäte, program och kön.',
    'antal', 'UKÄ', '97', 'Terminsvis', 'publik', false
  ),
  (
    'uka-soktryck-yrkesprogram',
    'Söktryck till yrkesexamensprogram',
    'Behöriga förstahandssökande per antagen till yrkesexamensprogram, efter lärosäte, program och kön.',
    'sökande per antagen', 'UKÄ', '99', 'Terminsvis', 'publik', false
  ),
  (
    'uka-examinerade',
    'Examinerade',
    'Examinerade efter lärosäte, examenskategori, examen, inriktning och kön.',
    'antal', 'UKÄ', '108', 'Årlig', 'publik', false
  ),
  (
    'uka-etablering',
    'Etablering på arbetsmarknaden',
    'Andel examinerade med etablerad ställning på arbetsmarknaden 1–1,5 år efter examen, efter lärosäte, examen och kön.',
    'procent', 'UKÄ', '136', 'Årlig', 'publik', false
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
