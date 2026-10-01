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
- Bortfall > max(1000, 2 %) stoppar finalisering om inte `confirm_large_removal` angetts manuellt.
- Första laddningen skrivs direkt men är osynlig (analysvyn kräver publicerad första laddning) tills finalisering. Avbruten laddning återupptas idempotent; annars `cleanup-initial`.

## Hash
`sha256` över kanonisk sträng, identisk i `R/etl/afr_normalize.R` och `afr_je_canonical`/`afr_ae_canonical`. SNI sorteras på rangordning + kod (bytevis), endast kod/rangordning/andel – aldrig klartext. Databasen räknar om hashen per post och avvisar avvikelser.

## Integritet
`peOrgNr` och `orgNr` endast i `afr_je_ident` (admin/ETL). Övriga tabeller använder `je_id`. Inga adresser, telefon, e-post, namn eller spärrar lagras (strikt validering avvisar sådana fält). Koordinater lagras men exponeras inte. Inget i sökindexet.

## Tabeller
`afr_syncs` (källdatum, hämtningstid, counts, statistik per körning), `afr_je_*`/`afr_ae_*` current/history/SNI, `afr_code_values` + `afr_code_value_history`, `afr_agkat_group` (fylls manuellt efter granskning av agKat-koder), vy `afr_ae_analysis`.

## Att göra själv
- Lägg `SCB_AFR_API_KEY` som GitHub Actions-secret.
- Kör `count-only` manuellt, granska volym, kör sedan `initial-load`.
