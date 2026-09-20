# E3 – SCB TAB6929

Första riktiga ETL-indikatorn är **Matchning – utbildning (E3)** från SCB:s PxWeb2-tabell `TAB6929`.

## Geografisk omfattning i första steget

Första versionen hämtar **län** via kodlistan `vs_CKM02Län`.

Arkitekturen ska senare kunna utökas med:

- Riket
- kommuner

utan att skapa ett separat ETL-system.

## Källa

- Tabell: `TAB6929`
- API: SCB PxWeb v2
- R-paket: `FaluPeppe/pxweb2r`
- Källa/styrande källa: SCB / `TAB6929`

SCB beskriver tabellen som E3, matchning mellan utbildning och yrke bland befolkningen 20–69 år.

## Urval

Urvalet motsvarar följande PxWeb2-query:

```text
ContentsCode             *
Tid                      *
SNI2007                  *
KonAlderFodelseland      *   codelist: vs_KonCKMRMI
Region                   *   codelist: vs_CKM02Län
Utbildning               *   codelist: vs_UtbildningsgruppE2-3N1-2
```

I `pxweb2r` ska detta uttryckas med `pxweb2_get_data()` och de aktuella kodlistorna/aggregationerna, inte genom handskrivna HTTP POST-anrop.

## Uppdateringskontroll

Morgonjobbet ska först använda metadatafunktionerna i `pxweb2r`:

- `pxweb2_get_metadata("TAB6929")`
- `pxweb2_table_updated("TAB6929")`

Ny data ska endast hämtas när SCB:s källdatum är senare än det källdatum som senast publicerats för indikatorn.

RUS-konventionerna gäller:

- `kalla_uppdaterad_datum`
- `hamtad_datum`
- `tillganglighetsdatum = coalesce(kalla_uppdaterad_datum, hamtad_datum)`
- `styrande_kalla = TAB6929`

## Viktig begränsning i nuvarande ingest-endpoint

Den befintliga endpointen `/api/public/jobs/publish-indicator` accepterar högst:

- 50 000 observationer
- cirka 2 MB request body

E3-urvalet ovan omfattar alla tabellinnehåll, år, näringsgrenar, län och de valda kodlistorna för utbildning samt kön/ålder/födelseland. SCB:s egen tabellsida visar redan att urvalet överstiger 150 000 celler.

Det betyder att hela E3-datasetet **inte ska skickas som ett enda nuvarande publish-anrop**.

## Nästa backendsteg för E3

Innan det schemalagda E3-jobbet aktiveras behövs chunkad import med atomisk finalisering:

1. skapa ett import-/batch-id
2. skicka validerade observationer i mindre chunkar
3. lagra chunkarna i staging
4. verifiera förväntat antal chunkar/rader
5. finalisera hela batchen atomiskt för indikatorn
6. först därefter ersätta publicerad data
7. vid fel behålls föregående publicerade dataset

Detta bevarar samma säkerhetsprincip som `publish_indicator`, men fungerar även för stora datamängder.

## Datamodell

E3 innehåller flera tabellinnehåll med olika enheter (antal, procent och procentenheter). Därför ska `ContentsCode` bevaras som en dimension tillsammans med:

- näringsgren SNI 2007
- utbildning
- kön/ålder/födelseland

Geografi och period ligger i de gemensamma observationsfälten.

När R-flödet byggs ska både stabila koder och läsbara etiketter bevaras där `pxweb2r` exponerar dem.
