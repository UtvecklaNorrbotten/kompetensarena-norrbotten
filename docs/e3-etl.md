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
- utbildning
- kön/ålder/födelseland

Geografi och period ligger i de gemensamma observationsfälten.

När R-flödet byggs ska både stabila koder och läsbara etiketter bevaras där `pxweb2r` exponerar dem.

## Timeout, återförsök och verifiering (migration 0008)

E3 behåller 5 000 rader per chunk. Senaste urvalets 4 472 496 rader kräver
895 chunkar. 2 000 rader skulle kräva 2 237 chunkar och överskrida nuvarande
gräns på 1 000. Ändra därför inte chunkstorleken isolerat.

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
5. Kör workflowet med `finalize_test=true` och `test_mode=false`.
   Kontrollera att testindikatorns nya batch publiceras med korrekt radantal.
6. Kör därefter hela E3 med båda testflaggorna avstängda.
   Verifiera status `succeeded`, förväntat radantal och aktiv batch för
   `e3-matchning-utbildning`. Först då är fullimporten verifierad.

Den lokala regressionstesten bevisar inte att Lovable Clouds PostgREST har
laddat inställningen, och den bevisar inte prestanda för miljontals rader.
