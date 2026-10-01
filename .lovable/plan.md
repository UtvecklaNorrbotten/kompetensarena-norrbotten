# SCB Allmänna företagsregistret (AFR) – rikstäckande datalager med historik

Mål: ett robust, rikstäckande lager för juridiska enheter (JE) och arbetsställen (AE) med egen förändringshistorik från dag ett. Ingen ny publik frontend i detta steg – endast datagrund, synk och adminstatus.

## Vad som byggs

1. **Datakälla `scb-afr`** registreras i befintliga `data_sources`/`data_source_state` och syns automatiskt i adminvyn (/admin/datakallor) – ingen ny statuslösning.
2. **Kodtabeller** från AFR:s 19 kodtabell-endpoints (kod + klartext), med upptäckt och loggning när en tabell ändras. Telefon-/e-post-/reklamspärr hämtas inte.
3. **Aktuella tabeller** för AE och JE med endast de analytiska fälten i briefen (inga adresser, telefon, e-post, namn på fysiska personer). Näringsgrenar i egna radtabeller (rangordning, kod, andel, avdelning) så SNI går att fråga effektivt; primär = rangordning 1.
4. **Historik (SCD typ 2)**: en ny version skapas bara när hash över historiserade attribut ändras. Varje version har första/sista observation, SCB:s `senasteUppdateringsDatum`, hämtningstid, hash, ändringstyp (ny, SNI, geografi, storlek, status, ägarkategori, sektor, säte, omsättningsklass, ej längre observerad).
5. **Daglig synk** i GitHub Actions kl. ~06:00 svensk tid (efter SCB:s fönster runt 04:00):
   api-info → jämför källdatum → vid ändring: count för AE/JE → full paginerad hämtning (limit 5000, cursor tills `hasMore=false`) → staging → atomisk finalisering. Retry/backoff på 429/5xx med `Retry-After`.
6. **Atomisk publicering**: diff, historik, bortfall och uppdatering av current sker i en databasfunktion först när hela traverseringen är klar och kontrollerna godkänts. Avbruten körning lämnar publicerade data orörda och kan aldrig markera poster som borttagna.
7. **Körningslogg** i `data_source_runs.details`: källdatum, API-version, JE-/AE-count, sidor, hämtade/nya/ändrade/oförändrade/ej längre observerade, retries/429, ändringar per typ, körtid och överförd datamängd. Adminvyn visar detta generellt.
8. **Integritet**: `peOrgNr`/`orgNr` ligger bara i en skyddad mappningstabell (ingen åtkomst för inloggade eller anonyma); analyslagret använder en intern stabil JE-id. Koordinater lagras men exponeras inte. Inga AFR-data in i sökindexet.
9. **Analysvyer för senare bruk** (förberedda, inte publicerade): AE med ärvda JE-attribut, härledd ägarkontroll (Offentlig / Privat svensk / Privat utländsk från `agKat`), säte inom/utom arbetsställets län. `privPubl` beskrivs som privat/publikt AB.

## Viktigt vägval: skicka bara förändringar

Ett helt Sverigeuttag (sannolikt flera miljoner poster inkl. inaktiva) varje dag via våra importendpoints skulle ta lika lång tid som E3-importen (110+ min) och fylla databasen. Förslag:

- ETL-skriptet hämtar en kompakt lista med nuvarande hashvärden per objekt från en nyckelskyddad endpoint.
- Det skickar **alla id:n + hash** (litet) för fullständighetskontroll och bortfall, men **fullständiga poster bara för nya och ändrade**.
- Resultatet blir identiskt med full diff i databasen, men överföringen krymper kraftigt efter första laddningen.
- Första laddningen är en engångsstor import (chunkad, återupptagbar som AF-historiken).

## Före första fulla importen

Testkörning som endast loggar api-info, AE-count, JE-count och beräknat antal sidor. Därefter bedöms lagringsbehov innan full laddning körs.

## Det du själv behöver göra

- Lägga till `SCB_AFR_API_KEY` som GitHub Actions-secret (används bara i ETL:t, aldrig i webbplatsen eller databasen).
- Starta första testkörningen manuellt i GitHub Actions.

## Ej i detta steg

Frontend-analysvyn "Näringslivets struktur", enkätjämförelse/viktning, kartor med enskilda arbetsställen.

## Tekniska detaljer

- Migration (unikt namn, t.ex. `0019_scb_afr`): tabeller `afr_code_tables`, `afr_je_ident` (privat: je_id uuid ↔ peOrgNr, inga grants till anon/authenticated), `afr_je_current`, `afr_je_history`, `afr_je_sni`, `afr_ae_current`, `afr_ae_history`, `afr_ae_sni`, staging `afr_stage_je/ae` (+ `afr_stage_keys`) knutna till `etl_batches`. Index på län, kommun, SNI, anstKl, agKat, je_id. RLS på allt; läsning initialt bara admin. Seed av `data_sources` för `scb-afr`.
- Funktioner (security definer, grant endast till ETL-rollen, ingen generell DELETE): `afr_start_sync`, `afr_store_chunk` (checksumme-idempotent), `afr_finalize_sync` (kontroller: `hasMore=false`, mottagna nycklar = count ± tolerans, inga dubletter, bortfall < tröskel annars fel), `afr_abort_sync`, `afr_current_hashes` (paginerad).
- Hash: SHA-256 över kanoniskt JSON av historiserade fält, SNI sorterad på rangordning+kod; beräknas i R och verifieras i databasen.
- Endpoints under `/api/public/jobs/afr/*` med befintlig ETL-nyckel, rate limit och Zod-validering; återanvänder `etl-auth.server.ts` och batchmönstret.
- R: `R/etl/afr_*.R` (klient, normalisering, hash, synk) via `etl_api.R`; workflow `.github/workflows/etl-scb-afr-daily.yml` (cron 04:00 UTC + manuell körning med lägena `count-only`, `full`).
- Dokumentation i `docs/afr-etl.md` och regel i `AGENTS.md`.
