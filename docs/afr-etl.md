# SCB Allmänna företagsregistret (AFR)

Rikstäckande lager för juridiska enheter (JE) och arbetsställen (AE) med egen historik (SCD typ 2).

## Flöde
GitHub Actions (`.github/workflows/etl-scb-afr-daily.yml`, cron `0 4 * * *` = 05/06 svensk tid) kör `R/etl/afr_sync.R`.

Lägen: `count-only`, `initial-load`, `daily`, `cleanup-initial`.

Daily: api-info → jämför med `data_source_state.latest_successful_period` → count → 17 kodtabeller → full traversering
(limit 5000, `hasMore=false`) → count + api-info igen → hämta id+hash (`/afr/hashes`) → delta → start/chunk/finalize.

## Säkerhetsregler
- ETL avbryter om `hasMore=false` inte nås, om unika ≠ count, om count eller källdatum ändras under uttaget.
- Databasen (`afr_finalize_sync`) kontrollerar `tidigare + nya − bortfallna = source_count` och efter tillämpning att antalet i källan stämmer.
- AFR-klienten håller minst `SCB_AFR_MIN_INTERVAL_SEC` (standard 3 s) mellan anrop, fördubblar intervallet vid 429 (max 60 s), pausar i förväg om kvothuvuden visar att kvoten tar slut, och loggar väntetider under `throttle`.
- Bortfall > max(1000, 2 %) stoppar finalisering om inte `confirm_large_removal` angetts manuellt.
- Första laddningen skrivs direkt men är osynlig (analysvyn kräver publicerad första laddning) tills finalisering. Avbruten laddning återupptas idempotent; annars `cleanup-initial`.

## Hash
`sha256` över kanonisk sträng, identisk i `R/etl/afr_normalize.R` och `afr_je_canonical`/`afr_ae_canonical`. SNI sorteras på rangordning + kod (bytevis), endast kod/rangordning/andel – aldrig klartext. Databasen räknar om hashen per post och avvisar avvikelser.

## Integritet
`peOrgNr` och `orgNr` endast i `afr_je_ident` (admin/ETL). Övriga tabeller använder `je_id`. Kärntabellerna avvisar fortfarande namn, adresser och kontaktfält. Namn, adresser, adresskoordinater och export/importmarkering historiseras separat i adminskyddade `afr_profile_versions`; `afr_profile_current` innehåller endast senaste telefon/e-post. Se [profiler och bokslut](company-data/README.md). Koordinater lagras men exponeras inte. Inget i sökindexet.

## Tabeller
`afr_syncs` (källdatum, hämtningstid, counts, statistik per körning), `afr_je_*`/`afr_ae_*` current/history/SNI, `afr_code_values` + `afr_code_value_history`, `afr_agkat_group` (fylls manuellt efter granskning av agKat-koder), vy `afr_ae_analysis`.

## Att göra själv
- Lägg `SCB_AFR_API_KEY` som GitHub Actions-secret.
- Kör `count-only` manuellt, granska volym, kör sedan `initial-load`.

## Första laddningen: pausade index
Hjälpindex och kopplingskontroller (lista i `afr_deferred_ddl`) är borttagna medan första laddningen pågår. Före finalisering kör ETL `afr/maintenance` (fyller i `primary_sni` och bygger sedan ett index per anrop). En trigger på `afr_syncs` gör att ingen synk kan få status `succeeded`, och ingen daglig synk kan starta, förrän alla index finns och alla kopplingar är validerade. Om återuppbyggnaden misslyckas förblir AFR opublicerat; nästa körning fortsätter där den slutade.

## Återupptagning av daglig publicering
Innan SCB kontaktas kontrolleras senaste dagliga synk med status `receiving`.
Om alla datapaket finns återupptas samma publicering med ursprungligt källdatum.
En ofullständig överföring avbryts under samma databaslås innan ett nytt uttag börjar.
Publiceringsfel behåller staging och markeras inte som lyckade; nästa körning försöker igen.
Efter återupptagen publicering kontrolleras SCB i samma körning. Om källan har uppdaterats hämtas och publiceras nästa version innan profilkompletteringen startar.

`afr_finalize_sync` tar ett icke-väntande transaktionslås före radlåset och returnerar
`busy` om en publicering redan pågår. Databasoperationen har 600 s tidsgräns,
HTTP-klienten 660 s. Varje explicit återförsök läser först committed status;
automatiska HTTP-återförsök är avstängda för finalisering. Ett lyckat anrop kan
upprepas utan dubbel historik. Felstatus skrivs endast under databaslåset,
aldrig från ett sent HTTP-fel. Valideringsfel stoppar återförsöken för granskning.

Diagnostik finns i `afr_syncs.stats.last_publication_error` (SQLSTATE, SQL-kontext,
tidpunkt och tidsåtgång). Ett `busy`-svar ger även process-ID och blockerande
process-ID utan råa registerdata. API:t är fortsatt skyddat med ETL-nyckeln.
Migration `0047_afr_publication_recovery.sql` måste appliceras före den nya klienten.

## Namn-, adress- och bokslutskomplettering
Den tillagda importen beskrivs i [company-data/README.md](company-data/README.md). Befintlig strukturhistorik och kanoniska hash är oförändrade. Profilkomplettering återanvänder kärntraverseringens tillfälligt fångade källsvar och skickar bara ändringar.
