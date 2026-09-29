# Arbetsförmedlingen – månads-ETL

Arbetsförmedlingens längre tidsserier publiceras som Excel-filer på:

https://arbetsformedlingen.se/statistik/sok-statistik/tidigare-statistik-tidsserier

Det finns inget stabilt statistik-API för dessa serier. Kompetensarena använder därför
de publicerade Excel-filerna som källa.

## Primära filer

Produktionsflödet utgår från fem huvudfiler samt en stödfil för exakta riksvärden:

1. `web-sok-lan-kom-YYYY-MM.xlsx`
2. `web-inskrivna-arbetslosa-tid-utan-arbete-lan-kom-YYYY-MM.xlsx`
3. `web-inskrivna-arbetslosa-svag-konkurrensformaga-YYYY-MM.xlsx`
4. `web-arbetslosa-yrkesomrade-YYYY-MM.xlsx`
5. `web-inskrivna-arbetslosa-andel-av-bas-YYYY-MM.xlsx`
6. `web-tid-riket-YYYY-MM.xlsx` – stödkälla för exakta riksvärden för tid utan arbete

Filer med årsgenomsnitt och ">12 månader som andel av BAS" används inte som egna
produktionskällor eftersom de kan härledas från de primära månadsfilerna.

## Månadsgrind

Filnamnets `YYYY-MM` används som publiceringssignal.

Den schemalagda processen ska först bara läsa HTML-sidan och identifiera den senaste
länken för var och en av de fem filprefixen. Excel-filerna får laddas ned först när:

- alla sex nödvändiga filer finns,
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
- `tid-utan-arbete`: >6, >12 och >24 månader per kommun. Län summeras endast när publicerade kommunvärden medger en exakt summa.
- `web-tid-riket`: exakta riksvärden för samma mått; används eftersom kommunfilen innehåller sekretessmarkeringar `<5` som gör exakt rikssummering omöjlig från kommunraderna.
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
samma månadsleverans, eftersom ingen fullimport får ske förrän samtliga sex är synkroniserade.

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

`R/etl/af_normalize.R` normaliserar de sex nödvändiga källfilerna till samma långa struktur:

- `period`
- `geo_code`
- `geo_level`
- `sex`
- `dimension_type`
- `dimension_value`
- `measure_code`
- `measure_label`
- `value`

Geografiskt behålls hela Sverige: samtliga 290 kommuner och samtliga 21 län.
Riket skapas som en egen nivå med kod `00` genom summering av länsvärdena.

Kommunkoderna hämtas från SCB:s aktuella officiella kodlista vid körning och cacheas
i minnet. Om SCB-listan inte kan läsas som exakt 290 unika kommuner stoppas körningen.
Om ett kommunnamn från AF inte kan mappas till SCB-kod stoppas körningen också; kommuner
får alltså inte försvinna tyst.

Riket beräknas endast från län, aldrig från kommunerna. Ett riksvärde sätts till `NA`
om någon av de 21 länsposterna saknas eller är maskerad. Andelar ska inte summeras eller
medelvärdesberäknas; de beräknas senare från summerade täljare och nämnare.

Den manuella workflow-körningen `mode=validate` laddar ned de sex aktuella filerna,
normaliserar dem och publicerar ingenting. Överlappande mått används i stället som
regressionskontroller:

1. `web-sok-lan-kom` INSAL summerat över ålder mot tid-filens ARBETSLÖSA.
2. `svag-konkurrensformaga` SAMTLIGA mot tid-filens ARBETSLÖSA.
3. yrkesområden summerade inklusive `Uppgift saknas` mot tid-filens ARBETSLÖSA.
4. BAS-filens SOK-tal mot tid-filens ARBETSLÖSA.

En framtida produktionsimport ska bara tillåtas om dessa kontroller går igenom.


### Datamängd

Den tidigare prototypen behöll 21 län och 14 Norrbottenskommuner. Det nya urvalet
behåller 21 län och 290 kommuner, vilket innebär ungefär 8,9 gånger fler geografier före
riksraderna. Det är medvetet: vi undviker att kasta bort nationell kommuninformation
innan vi vet den faktiska normaliserade kostnaden.

Dry-runen rapporterar därför för varje källa:

- antal normaliserade rader,
- ungefärlig storlek i R-minnet,
- att 290 kommuner, 21 län och Riket finns,
- antal riksrader som blir `NA` på grund av saknade/maskerade länsvärden,
- total radmängd och ungefärlig minnesstorlek för alla fem dataset.

Beslut om eventuell framtida filtrering ska tas utifrån dessa faktiska mått, inte utifrån
Excel-filernas komprimerade filstorlek.


### Varför en separat riketsfil behövs för tid utan arbete

Valideringskörningen visade att län/kommun-filen inte innehåller explicita länstotaler.
Den innehåller 290 kommuner plus restkategorin `Uppgift saknas`, och vissa små tal är
sekretessmarkerade som `<5`. Därför går det inte att återskapa exakta läns- eller
riksvärden genom att bara summera kommunerna.

För denna källa gäller därför:

- kommunvärden behålls som publicerade,
- länsvärden härleds endast när alla komponenter är numeriska; annars blir länsvärdet `NA`,
- Riket hämtas från Arbetsförmedlingens separata riketsfil,
- övriga AF-källor fortsätter använda länsvärden som källa för beräknat Riket när kompletta länsrader finns.


### Riketsfilen för tid utan arbete

`web-tid-riket-YYYY-MM.xlsx` består av bladen `SQL-kod`, `Info` och `Tabell`.
Den synliga tabellen visar totalserien, medan kön, ålder, födelseland och
utbildningsnivå ligger som pivottabellsdimensioner. Produktionsläsningen ska därför
inte försöka hitta separata blad för dessa dimensioner.

Riketsvärden läses direkt ur `pivotCacheDefinition1.xml` /
`pivotCacheRecords1.xml`. Cachefälten är:

- `PERIOD`
- `KOEN`
- `ALDGR`
- `FH`
- `FLAND`
- `UTBILDNING`
- `INSAL`
- `UA06`
- `UA12`
- `UA24`

Rikets >6, >12 och >24 månader summeras ur cachen på exakt samma dimensionsnivåer som
kommunfilen använder. För augusti 2026 ger cachen totalerna 214 835, 149 016 respektive
83 001, vilket överensstämmer med den synliga tabellen i arbetsboken.


### BAS: län och Riket

`web-inskrivna-arbetslosa-andel-av-bas` har, liksom filen för tid utan arbete,
kommuner i pivot-cachen men inga explicita länsrader. Till skillnad från tid-filen är
BAS-nämnarna numeriska och additiva, så län kan härledas exakt genom att summera
kommunerna inom respektive län. Riket skapas därefter från de 21 länsvärdena.

Kontroll mot den faktiska augusti 2026-filen visar att summan av samtliga 290 kommuners
`TOTAK` är 5 354 201,083333336, exakt samma värde som visas för Riket i bladet
`Antal`. Det bekräftar att denna aggregeringsväg är korrekt för BAS-nämnarna.


### web-sok: kommun, län och Riket

Inspektion av den faktiska filen `web-sok-lan-kom-2026-08.xlsx` visar att
pivot-cacherna inte innehåller färdiga länsrader. Geografin består av 290 kommuner,
21 län i fältet `LAN` samt restkategorier för saknad kommun och saknat län.

Därför byggs geografin så här:

- kommun: endast de 290 namngivna kommunerna,
- län: summan av alla rader med känt län, inklusive rader där kommunen saknas,
- Riket: summan av samtliga råa rader, även `LAN = Uppgift saknas`.

Det sista är viktigt. För 2026-08 finns 119 inskrivna arbetslösa i ålderscachen med
saknat län. Om Riket skapades enbart genom att summera de 21 länsvärdena skulle dessa
personer falla bort. Summering av hela råcachen ger 349 398 inskrivna arbetslösa för
2026-08, vilket exakt överensstämmer med `INSAL` i den separata riketsfilen
`web-tid-riket-2026-08.xlsx`.


### Svag konkurrensförmåga och yrkesområde: geografi

Valideringen av de faktiska 2026-08-filerna visar att inte heller dessa källor ska
tolkas som om blanka kommunfält vore färdiga länstotaler.

- `svag konkurrensförmåga`: inga explicita länsrader finns. Län byggs från alla
  rader med känt län och Riket från hela råcachen.
- `yrkesområde`: det förekommer blanka kommunfält tillsammans med känt län. Dessa
  är restposter för saknad kommun, inte länstotaler. De ingår därför i länssumman
  men publiceras inte som kommun. Riket byggs från hela råcachen.

För `svag konkurrensförmåga` summerar `SAMTLIGA` i 2026-08 till 349 398
(171 986 kvinnor och 177 412 män), samma total som övriga kontrollkällor.
119 personer saknar län och måste därför tas med direkt från råcachen för att
Riket inte ska underskattas.
