# E3 – SCB TAB6929

## Kommunimport (2026-10-04)

Kommunhämtningen är en separat indikator, `e3-matchning-utbildning-kommun`,
med entrypoint `R/etl/e3_municipal.R` och workflow **ETL - E3 alla kommuner**.
Den befintliga länsimporten behåller sina utbildningsnivåer och könskategorier.
Kommunimporten väljer:

- alla 290 kommuner via `vs_CKM03Kommun`
- alla år (vid metadata-kontroll: 2019–2024)
- alla 87 värden i `vs_UtbildningsgruppE2-3N1-2`, inklusive totalgruppen
- alla 17 näringsgrensvärden, inklusive total och uppgift saknas
- alla innehåll utom `000008QW` (skillnad mellan förvärvsgrader)
- endast `totalt` i den obligatoriska kön/ålder/födelseland-variabeln

Inriktning och nivå hämtas inte separat. De sju innehållen inkluderar D
(`000008QS`), justerad förvärvsgrad och matchad förvärvsgrad.
Aktuell full cellprodukt är **18 014 220 rader**. Tomma/sekretessmarkerade
celler bevaras som null, aldrig som noll. De kan inte antas minska radantalet.
Totaler och undergrupper får inte summeras tillsammans.

### Strömning och återstart

En SCB-del omfattar ett år, en utbildningsgrupp och normalt alla kommuner:
34 510 celler, under cellgränsen 150 000. Kommunlistan delas ytterligare om
dimensionerna växer. Enbart aktuell del ligger i minnet och skrivs sekventiellt
i högst 5 000 rader per chunk. Planen har för närvarande 522 SCB-delar och
3 654 chunkar (avrundning sker per SCB-del).

Migration **0031** höjer batchgränsen till 10 000 i databas, API och R-klient.
Chunkstorlek och HTTP-gränser höjs inte. Den lägger till importnyckel,
kontrollindikator och två nyckelskyddade RPC-funktioner. Importnyckeln är SHA-256
över källans versionsdatum, hela urvalet, indikator, testläge och planversion.
Återstart väljer endast en batch med identisk nyckel och verifierad,
sammanhängande chunkföljd. En delvis sparad SCB-del spelas om; befintliga
checksummor måste stämma. Färdiga delar behöver inte hämtas igen.

SCB:s versionsdatum kontrolleras inför varje del och före finalisering.
Om det ändras stoppas publiceringen och ett nytt snapshot får byggas.
Skyddet förutsätter att SCB ändrar metadata vid en revision; det kan inte
upptäcka en ändring som SCB gör utan uppdaterad versionsmarkör.
Planen förutsätter en komplett cellprodukt inklusive nullvärden. Avvikande
radantal eller dubbletter stoppas innan den delen skrivs.

Vid fel behålls sparade chunkar för återstart. Workflowet pausar kontrollerat
efter fyra timmars importtid och fortsätter automatiskt nästa körning.
Ingen delimport publiceras. Finaliseringen verifierar totalsumman och byter
aktiv version atomiskt. Samma SCB-version hämtas inte igen efter en lyckad
publicering om inte `force_refresh` väljs.

### Driftsättning och verifiering

1. Driftsätt backend och applicera **0031_e3_municipal_snapshot.sql** och
   **0032_e3_municipal_aggregates.sql** via Lovable. Uppdatera befintlig
   migrationsjournal; skapa inte dubbletter av migrationerna.
2. PR-workflowet **Validate E3 municipal** kontrollerar R-syntax, syntetiska
   regressionsexempel och ett faktiskt SCB-prov utan databasåtkomst.
3. Merge av importkoden till main startar kommunworkflowet. Det väntar i upp
   till tio minuter på backend/migration 0031. Om driftsättningen dröjer ska
   körningen köras om efter driftsättning.
4. Manuellt `test_mode=true` stagedar två kommuner och två utbildningsgrupper
   på en separat adminindikator och avbryter utan publicering.
   `finalize_test=true` prövar atomisk publicering på samma adminindikator.
5. Fullimport använder båda testflaggorna false. Verifiera workflowloggen:
   18 014 220 rader, status succeeded och aktiv batch för kommunindikatorn.
   En lyckad körning med meddelandet **Import pausad** är endast en checkpoint.
6. Migration 0032 inkluderar kommunerna i `agg_e3_matchning` och dess timvisa
   uppdateringskontroll. D samt SCB:s två andelar bevaras. Kommuner summeras
   inte till län/Riket; dessa fortsätter komma från befintliga länsdata.
   Endast utbildningsgrupper används i detta aggregat för att undvika att
   alternativa utbildningsindelningar blandas.

Schemat kontrollerar källan dagligen omkring **05:30 svensk tid** och
fortsätter ofullständiga importer. Lagringsbehov och faktisk inskrivningstid
måste verifieras i drift: 18 miljoner observationer med dimensioner och index
kan kräva flera GB. Regressionstester visar inte produktionsprestanda.

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
Utbildning               *   codelist: vs_Utbildningsnivå19RMI
```

Kodlistorna är två alternativa indelningar av samma SCB-variabel och hämtas
därför i separata PxWeb2-anrop. De korsas inte med varandra. Resultaten binds
ihop före publicering och skiljs åt med:

- `utbildning_indelning_code`: `grupp` eller `niva`
- `utbildning_indelning_label`: läsbart namn
- `utbildning_codelist`: exakt SCB-kodlista

Indelningen ingår i den logiska observationsnyckeln. Kodvärden från olika
kodlistor kan därför aldrig sammanblandas. I `pxweb2r` uttrycks urvalet med
`pxweb2_get_data()` och explicit `codelist` på kön, region och utbildning,
inte genom handskrivna HTTP POST-anrop.

## Uppdateringskontroll

Morgonjobbet använder den gemensamma SCB-hjälparen i `R/etl/scb_common.R`. Den jämför tidpunkten för senaste lyckade publicering med SCB via `pxweb2_table_needs_update()`. Om tabellen inte är nyare loggas `no_change` och ingen statistikdata hämtas.

Den manuella workflow-parametern `force_refresh` används när själva
ETL-definitionen har ändrats, exempelvis när utbildningsnivå införs, trots att
SCB:s metadata är oförändrad. Schemalagda körningar använder alltid den vanliga
metadatajämförelsen.

När data behöver uppdateras hämtas tabellmetadata med `pxweb2_get_metadata("TAB6929")` och samma metadataobjekt återanvänds i den efterföljande datahämtningen.

RUS-konventionerna gäller:

- `kalla_uppdaterad_datum`
- `hamtad_datum`
- `tillganglighetsdatum = coalesce(kalla_uppdaterad_datum, hamtad_datum)`
- `styrande_kalla = TAB6929`

## Storlek: E3 ska publiceras chunkat

Den enkla endpointen `/api/public/jobs/publish-indicator` accepterar högst 50 000
observationer och cirka 2 MB request body. E3-urvalet omfattar alla tabellinnehåll, år,
näringsgrenar, län och de valda kodlistorna för utbildning samt kön/ålder/födelseland —
över 150 000 celler. Hela E3-datasetet ska därför **inte** skickas som ett enda
publish-anrop.

## Chunkad import (byggd)

Det chunkade flödet finns nu i backend och ska användas för E3:

1. `POST /api/public/jobs/etl-batch/start` — skapar `batch_id`, anger indikator, källa,
   förväntat antal chunkar och (valfritt) förväntat antal rader
2. `POST /api/public/jobs/etl-batch/chunk` — validerade observationer i mindre chunkar,
   skrivs till en ny, ännu osynlig batch-version
3. `POST /api/public/jobs/etl-batch/finalize` — verifierar antal chunkar/rader och
   växlar atomiskt indikatorns aktiva batch-version
4. `POST /api/public/jobs/etl-batch/abort` — markerar batchen som misslyckad och
   gör den omedelbart osynlig; eventuell städning kan ske separat

Vid fel behålls föregående publicerade dataset oförändrat. Finaliseringen flyttar inte
miljontals rader, utan byter bara referensen till den färdiga versionen. Samma
säkerhetsprincip som `publish_indicator` gäller: nyckelskyddad endpoint, advisory lock
per indikator, ingen generell databasåtkomst. Fullständigt format, statuskoder och
begränsningar finns i `docs/utveckla.md`.

Rekommendation för E3: dela datasetet på exempelvis län eller år, med högst 20 000
observationer per chunk.

## Datamodell

E3 innehåller flera tabellinnehåll med olika enheter (antal, procent och procentenheter). Därför ska `ContentsCode` bevaras som en dimension tillsammans med:

- näringsgren SNI 2007
- utbildning, som alternativt kan visas efter utbildningsgrupp eller utbildningsnivå
- kön/ålder/födelseland

Geografi och period ligger i de gemensamma observationsfälten.

När R-flödet byggs ska både stabila koder och läsbara etiketter bevaras där `pxweb2r` exponerar dem.

Utbildningsnivå och utbildningsgrupp är officiella, separat hämtade SCB-värden.
Andelar summeras eller medelvärdesberäknas inte mellan indelningarna.

## Timeout, återförsök och verifiering (migration 0008)

E3 skickar chunkar sekventiellt om högst 5 000 rader. Payloaden byggs
vektoriserat i R (kolumnvis uppslagning i stället för radslicing), vilket är den
stora tidsvinsten. Ett försök med 3 parallella chunkar à ~10 000 rader slog i
databasens 30-sekundersgräns: samtidiga insättningar konkurrerar om samma tabell,
index och batchradens lås. Parallell sändning (`req_perform_parallel`) är därför
borttagen. Varje chunk skickas med befintlig retry-logik (upp till 5 försök vid
429/502/503/504) och inväntas innan nästa byggs. Skriptet räknar det faktiska
antalet chunkar före batchstart och stoppar utan publicering om gränsen 2 000
överskrids.



Migration `0008_etl_chunk_timeout_and_retry.sql` sätter
`statement_timeout = '30s'` i deklarationen för `etl_store_chunk` och begär
omladdning av PostgRESTs schemacache. Rollernas inställningar ändras inte.
PostgREST måste stödja och tillåta att funktionens `statement_timeout` lyfts
till transaktionen (`db-hoisted-tx-settings`).
Se [Supabases timeoutdokumentation](https://supabase.com/docs/guides/database/postgres/timeouts).

Samma sista chunk kan nu återförsökas när batchen har status `ready`.
Checksumman måste stämma; ett annat innehåll ger fortfarande konflikt.
Timeout, låstimeout, deadlock och serialiseringsfel ger HTTP 503.
R-klienten försöker högst fem gånger vid 429/502/503/504 eller transportfel
för chunk, finalisering, avbrott och statusläsning. httr2 använder väntetid
med slumpmässig exponentiell ökning och respekterar Retry-After.
Varje HTTP-försök har 60 sekunders timeout. Batchstart och no-change
upprepas inte automatiskt eftersom de kan skapa nya poster.
Se [httr2 req_retry](https://httr2.r-lib.org/reference/req_retry.html).

Workflowloggen skiljer på byggandet av observationer i R, JSON-kodning och
HTTP-tid inklusive återförsök. Serverns `rpc_ms` omfattar databas-RPC inklusive
transport till PostgREST och avser det senaste försöket, inte ren SQL-tid.
Serverloggen innehåller även RPC-tid och felkod för misslyckade försök.

### Driftsättning

1. Applicera befintliga migrationer i ordning och sedan exakt migration 0008.
   Registrera den befintliga journalposten; skapa inte en kopia med nytt nummer.
2. Kontrollera funktionens `proconfig` i `pg_proc`: den ska innehålla
   `statement_timeout=30s` och `search_path=public`. Kontrollera att endast
   serverrollen (utöver ägaren) får köra funktionen.
3. Bekräfta att PostgRESTs schemacache laddats om och att dess version och
   konfiguration tillämpar funktionens timeout före RPC-anropet.
   En SQL-editor med 120 sekunders timeout verifierar inte API-vägen.
4. Kontrollera att serverkoden med HTTP 503 och `rpc_ms` är driftsatt.
5. Kör workflowet med `finalize_test=true`, `test_mode=false` och
   `force_refresh=false`.
   Kontrollera att testindikatorns nya batch publiceras med korrekt radantal.
6. Kör därefter hela E3 med båda testflaggorna avstängda och
   `force_refresh=true`, eftersom SCB:s metadata kan vara oförändrad när den nya
   utbildningsindelningen tas i drift.
   Verifiera status `succeeded`, förväntat radantal och aktiv batch för
   `e3-matchning-utbildning`. Kontrollera även att både `grupp` och `niva`
   finns och att antalet per indelning motsvarar workflowloggen. Först då är
   fullimporten verifierad. Efter införandet ska `force_refresh` åter vara
   `false`.

Den lokala regressionstesten bevisar inte att Lovable Clouds PostgREST har
laddat inställningen, och den bevisar inte prestanda för miljontals rader.


## Gemensam SCB-struktur

E3 är fortfarande indikator-specifik där det behövs: urval, transformation, dimensionskoder och tekniska rimlighetskontroller ligger i `R/etl/e3_tab6929.R`.

Följande delar är däremot gemensamma för SCB-indikatorer:

- metadata-/uppdateringskontroll i `scb_prepare_run()`
- hämtning av SCB-kodlistor i `scb_get_codelist_codes()`
- uppdelning mot SCB:s cellgräns i `scb_split_dimension_by_cell_limit()`
- standardisering av variabelnamn/kodkolumner
- endpoint-anrop, retry och chunkad publicering i `etl_api.R`
- GitHub Actions via `etl-scb-indicators.yml`

Nya indikatorer ska inte pressas in i E3-logik. Varje indikator behåller sin egen query och validering, medan gemensam infrastruktur återanvänds.
