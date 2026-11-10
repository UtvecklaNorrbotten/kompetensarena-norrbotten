# Skolverket – skolresultat

## Omfattning

Kompetensarena hämtar tills vidare sex avgränsade indikatorer från Skolverkets SIRIS-exporter:

| Indikator | SIRIS-export | Urval | Historik |
| --- | ---: | --- | ---: |
| Behörighet till gymnasieskolans nationella program | 5 | Åk 9, Samtliga, behörig till yrkesprogram | 10 läsår |
| Grundläggande högskolebehörighet | 88 | Nationella program | 10 läsår |
| Gymnasieexamen | 88 | Nationella program | 10 läsår |
| Gymnasieexamen inom 3 år | 360 | Gymnasieskolan totalt | 10 startläsår |
| Gymnasieexamen inom 4 år | 405 | Gymnasieskolan totalt | 10 startläsår |
| Gymnasieexamen inom 5 år | 410 | Gymnasieskolan totalt | 10 startläsår |

Övrig gymnasiestatistik ingår inte i denna import.

## Källa

Direkt API-källa:

- metadata: `https://siris.skolverket.se/siris/reports/export_api/lasar/`
- CSV-export: `https://siris.skolverket.se/siris/reports/export_api/runexport/`

Ingen webbläsarautomatisering behövs.

## Datamodell

Plattformens geografier är Riket, län och kommun. Skolenhet är därför inte en egen `geo_code`.

- `geo_code` = skolkommunens fyrsiffriga kommunkod
- skolenhetskod och skolnamn = dimensionsfält
- länskod = de två första siffrorna i kommunkoden
- huvudmannatyp bevaras som dimension

Det gör det möjligt att filtrera skolor inom kommuner utan att införa en ny geografisk nivå.

Kommun- och länsvärden får inte skapas som enkla medelvärden av skolornas procenttal. Sådana aggregat behöver antingen officiella källvärden eller täljare/nämnare.

## Sekretess och saknade värden

SIRIS använder bland annat `.`, `..` och `~100` när ett exakt värde inte ska redovisas eller inte finns. ETL:n publicerar bara strikt numeriska källvärden som exakta procenttal. Markerade värden utelämnas.

## Uppdatering

Workflow:

`.github/workflows/etl-skolverket.yml`

- körs första dagen varje månad
- kan köras manuellt i testläge
- testläge hämtar och validerar hela tioårsurvalet utan databaspublicering
- produktionsläge ersätter respektive indikator atomiskt via befintlig ETL-batchinfrastruktur

## Kvalitetskontroller

Importen stoppas om:

- någon indikator inte har exakt 10 perioder
- skolenhetskod inte är åtta siffror
- kommunkod inte är fyra siffror
- ett publicerat värde ligger utanför 0–100
- dubbletter finns för indikator × kommun × period × skolenhet
- inga Norrbottensskolor finns i underlaget
- Skolverket ändrar förväntade kolumnnamn eller genomströmningsdefinitioner

Live-test på riktiga SIRIS-filer 2026-11-10 gav:

- åk 9 gymnasiebehörighet: 11 540 exakta skolenhetsvärden
- grundläggande högskolebehörighet: 9 134
- gymnasieexamen: 10 676
- genomströmning 3 år: 9 303
- genomströmning 4 år: 9 368
- genomströmning 5 år: 9 148

Samtliga hade exakt 10 perioder.
