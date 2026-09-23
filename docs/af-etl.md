# Arbetsförmedlingen – månads-ETL

Arbetsförmedlingens längre tidsserier publiceras som Excel-filer på:

https://arbetsformedlingen.se/statistik/sok-statistik/tidigare-statistik-tidsserier

Det finns inget stabilt statistik-API för dessa serier. Kompetensarena använder därför
de publicerade Excel-filerna som källa.

## Primära filer

Produktionsflödet utgår från fem filer:

1. `web-sok-lan-kom-YYYY-MM.xlsx`
2. `web-inskrivna-arbetslosa-tid-utan-arbete-lan-kom-YYYY-MM.xlsx`
3. `web-inskrivna-arbetslosa-svag-konkurrensformaga-YYYY-MM.xlsx`
4. `web-arbetslosa-yrkesomrade-YYYY-MM.xlsx`
5. `web-inskrivna-arbetslosa-andel-av-bas-YYYY-MM.xlsx`

Filer med årsgenomsnitt och ">12 månader som andel av BAS" används inte som egna
produktionskällor eftersom de kan härledas från de primära månadsfilerna.

## Månadsgrind

Filnamnets `YYYY-MM` används som publiceringssignal.

Den schemalagda processen ska först bara läsa HTML-sidan och identifiera den senaste
länken för var och en av de fem filprefixen. Excel-filerna får laddas ned först när:

- alla fem filer finns,
- alla fem har samma `YYYY-MM`,
- perioden är nyare än senast lyckade fullimport.

Exempel: om fyra filer heter `2026-09` och en fortfarande heter `2026-08` görs ingen
nedladdning. Nästa kontroll väntar tills även den femte filen är uppdaterad.

Det innebär att den dagliga kontrollen är mycket liten. De stora Excel-filerna hämtas
normalt bara en gång per ny månadsperiod.

### När kontrollen startar

Den 23 september 2026 visar Arbetsförmedlingens sida fortfarande augusti 2026 för de fem
primärkällorna. Det ger oss en praktisk, men inte garanterad, tumregel: börja kontrollera
från den 23:e i månaden efter statistikmånaden. Workflowet kör därför dagligen den
23:e–31:e. När fullimporten senare kopplas på kommer samma grind att göra att filerna
bara laddas ned när alla fem har gått över till samma nya period.

Fältet `check_from_day_of_month = 23` i källregistret betyder alltså **startdag för
kontroll**, inte ett löfte om Arbetsförmedlingens publiceringsdatum.

## Filintegritet

Efter nedladdning kontrolleras minst:

- filen finns och har rimlig storlek,
- filsignaturen är ZIP/XLSX,
- SHA-256 beräknas och sparas i körningens manifest.

Hashen används som teknisk kontroll och revisionsspår för den fil som faktiskt hämtats.
Den automatiska månadsgrinden bygger däremot på filnamnets period. En tyst ersättning av
samma `YYYY-MM`-fil upptäcks därför inte utan en separat kontroll av exempelvis
HTTP-header eller en medveten omhämtning. Det kan läggas till senare om behovet uppstår.

## Importstrategi

Kanoniskt format är långt format. Överlappande mått importeras endast från sin valda
primärkälla och används i övriga filer som korsvalidering.

Planerade ansvarsområden:

- `web-sok-lan-kom`: grundtal och bakgrundsdimensioner.
- `tid-utan-arbete`: >6, >12 och >24 månader.
- `svag-konkurrensformaga`: UTSATTA; SAMTLIGA används som kontroll.
- `yrkesomrade`: arbetslösa per yrkesområde.
- `andel-av-bas`: BAS-arbetskraftens nämnare; SOK-tal används som kontroll.

AF-specifik källupptäckt och nedladdning ligger i `R/etl/af_common.R`.
Källregistret ligger i `R/etl/af_sources.R`.

## Nästa steg

Nästa steg är att implementera och verifiera fem filspecifika normaliseringar till
långformat samt korsvalideringar mellan överlappande mått. För pivotbaserade filer ska
underliggande pivot-cache läsas i stället för att automatisera klick i Excel.


## Övergripande källstatus

AF använder samma generella källregister som övriga ETL-flöden:

- `data_sources` beskriver källan och dess kontrollfrekvens.
- `data_source_state` håller senaste observerade period, senaste lyckade period,
  senaste kontrolltid, senaste lyckade hämtning och aktuell status.
- `data_source_runs` får `source_id`, `source_period` och `details` för historik.

AF:s samlade käll-ID är `af-monthly`. De fem Excel-filerna behandlas som komponenter i
samma månadsleverans, eftersom ingen fullimport får ske förrän samtliga fem är synkroniserade.

Statusarna används så här:

- `waiting`: filerna visar olika månader.
- `ready`: alla fem visar samma nya månad och kan importeras.
- `no_change`: den gemensamma månaden är redan importerad.
- `succeeded`: fullimporten för perioden lyckades.
- `failed`: kontroll eller import misslyckades.


## Normalisering och månatlig kvalitetskontroll

Pivotbaserade AF-filer läses strömmande med SAX via `R/etl/af_pivot_cache.R`.
Det är viktigt eftersom exempelvis yrkesområdesfilens okomprimerade pivot-cache kan vara
flera hundra MB och inte bör byggas som ett helt XML-träd i minnet.

`R/etl/af_normalize.R` normaliserar de fem primärkällorna till samma långa struktur:

- `period`
- `geo_code`
- `geo_level`
- `sex`
- `dimension_type`
- `dimension_value`
- `measure_code`
- `measure_label`
- `value`

Geografiskt behålls alla län som jämförelse samt Norrbottens 14 kommuner. Övriga
kommuner filtreras bort redan under pivotläsningen för att minska minne och datamängd.

Den manuella workflow-körningen `mode=validate` laddar ned de fem aktuella filerna,
normaliserar dem och publicerar ingenting. Överlappande mått används i stället som
regressionskontroller:

1. `web-sok-lan-kom` INSAL summerat över ålder mot tid-filens ARBETSLÖSA.
2. `svag-konkurrensformaga` SAMTLIGA mot tid-filens ARBETSLÖSA.
3. yrkesområden summerade inklusive `Uppgift saknas` mot tid-filens ARBETSLÖSA.
4. BAS-filens SOK-tal mot tid-filens ARBETSLÖSA.

En framtida produktionsimport ska bara tillåtas om dessa kontroller går igenom.
