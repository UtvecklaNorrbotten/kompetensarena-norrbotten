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

## Filintegritet

Efter nedladdning kontrolleras minst:

- filen finns och har rimlig storlek,
- filsignaturen är ZIP/XLSX,
- SHA-256 beräknas och sparas i körningens manifest.

Hashen ska användas som teknisk kontroll. Filperioden styr om en ny månad ska importeras,
men ett förändrat hashvärde för samma månad ska kunna flaggas som en källrevision.

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
