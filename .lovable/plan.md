# SCB Allmänna företagsregistret (AFR) – rikstäckande datalager med historik

Mål: ett robust, rikstäckande lager för juridiska enheter (JE) och arbetsställen (AE) med egen förändringshistorik från dag ett. Ingen ny publik frontend i detta steg – endast datagrund, synk och adminstatus.

## Vad som byggs

1. **Datakälla `scb-afr`** registreras i befintliga `data_sources`/`data_source_state` och syns automatiskt i adminvyn (/admin/datakallor) – ingen ny statuslösning.
2. **Kodtabeller**: de 17 analytiskt relevanta av AFR:s 20 kodtabell-endpoints hämtas (kod + klartext). De tre spärrtabellerna (telefon, e-post, reklam) hämtas inte. Ändringar i kodtabeller upptäcks, historiseras och loggas separat.
3. **Aktuella tabeller** för AE och JE med endast de analytiska fälten i briefen (inga adresser, telefon, e-post, namn på fysiska personer). Näringsgrenar i egna radtabeller (rangordning, kod, andel, avdelning) så SNI går att fråga effektivt; primär = rangordning 1.
4. **Historik (SCD typ 2)**: en ny version skapas bara när hash över historiserade attribut ändras. Varje version (rad) har första/sista observation, hash och `change_types` som lista (t.ex. `["SNI", "storlek"]`, möjliga värden: ny, SNI, geografi, storlek, status, ägarkategori, sektor, säte, omsättningsklass, ej längre observerad), samt en referens till synkkörningen. SCB:s `senasteUppdateringsDatum` och hämtningstid lagras en gång per körning (inte på varje rad) och nås via den referensen.
5. **SNI-historik per objekt**: varje historikversion har sina egna SNI-rader (kod, rangordning, andel) kopplade till versionen, så att tidigare SNI kan rekonstrueras exakt – inte bara att "SNI ändrades". Hashen bygger på SNI-kod, rangordning och andel, aldrig på klartext; en ändrad klartext i kodtabellen gör alltså inga JE/AE ändrade. Ingen SNI 2007 → 2025-mappning i detta steg.
6. **Daglig synk** i GitHub Actions kl. 04:00 UTC (05:00 svensk vintertid, 06:00 sommartid – efter SCB:s nattliga underhåll):
   api-info → jämför källdatum → vid ändring: count för AE/JE → full paginerad hämtning (limit 5000, cursor tills `hasMore=false`) → count igen → delta → atomisk finalisering. Retry/backoff på 429/5xx med `Retry-After`.
7. **Atomisk publicering**: diff, historik, bortfall och uppdatering av current sker i en databasfunktion först när hela traverseringen är klar och kontrollerna godkänts. Avbruten körning lämnar publicerade data orörda och kan aldrig markera poster som borttagna.
8. **Körningslogg** i `data_source_runs.details`: källdatum, API-version, JE-/AE-count (före/efter), sidor, hämtade/nya/ändrade/oförändrade/ej längre observerade, retries/429, ändringar per typ, kodtabellsändringar, körtid och överförd datamängd. Adminvyn visar detta generellt.
9. **Integritet**: både `peOrgNr` och `orgNr` ligger bara i en skyddad identifieringstabell, eftersom JE även kan vara fysiska personer. `orgNr` kan användas server-side/av admin för matchning mot annan registerdata, men exponeras aldrig för anonyma eller vanliga inloggade, ligger inte i publika vyer och skickas inte till sökindexet. Current/history och analyslagret använder en intern stabil `je_id`. Koordinater lagras men exponeras inte. Inga AFR-data in i sökindexet.
10. **Analysvyer för senare bruk** (förberedda, inte publicerade): AE med ärvda JE-attribut, härledd ägarkontroll (Offentlig / Privat svensk / Privat utländsk från `agKat`), säte inom/utom arbetsställets län. `privPubl` beskrivs som privat/publikt AB.

## Viktigt vägval: läs hela AFR, skicka bara förändringar

Ett helt Sverigeuttag varje dag via våra importendpoints skulle ta lika lång tid som E3-importen (110+ min) och fylla databasen. Flöde:

1. ETL hämtar befintliga id + hash från en hash-endpoint som är nyckelskyddad, paginerad, gzip-komprimerad och bara nås server-side (ETL), aldrig från webbplatsen.
2. ETL traverserar hela AFR för JE och AE.
3. ETL räknar deterministiska hashvärden.
4. ETL delar upp i nya, ändrade, bortfallna och oförändrade.
5. Endast fullständiga nya poster, fullständiga ändrade poster och id för bortfallna skickas till import-API:t. Hela nyckelbeståndet skickas inte tillbaka.

**Fullständighetskontroll i ETL** – alla krav måste uppfyllas, annars avbryts körningen utan att något skickas:
- `hasMore=false` nåddes korrekt.
- `unique_observed_count == source_count` (exakt, ingen tolerans).
- count före och efter traverseringen är lika; annars avbryts synken och körs om senare.

Bryts SCB-anropet på sida 137 av 400 avbryts körningen och inget markeras som borttaget.

**Databasens slutkontroll** före finalisering, för JE och AE var för sig:
- `tidigare current + nya − bortfallna = source_count`, annars publiceras inte batchen.
- Säkerhetströskel för ovanligt stora bortfall; överskrids den stoppas finaliseringen för manuell kontroll.

**Deterministisk hash** i R och databasen: fasta fält i fast ordning, normaliserade tomvärden och datumformat, SNI-listor sorterade på rangordning och kod, ingen klartext. Databasen räknar om hashen på mottagna poster och avvisar avvikelser.

## Första laddningen

Separat från den dagliga deltaöverföringen: chunkad, återupptagbar och atomiskt finaliserad (som AF-historiken).

Innan den startar körs `count-only` och redovisar: JE-count, AE-count, antal API-sidor vid limit=5000, uppskattad lagringsmängd och uppskattad storlek på första importen. Full laddning startas inte förrän detta är granskat.

## Det du själv behöver göra

- Lägga till `SCB_AFR_API_KEY` som GitHub Actions-secret (används bara i ETL:t, aldrig i webbplatsen eller databasen).
- Starta första `count-only`-körningen manuellt i GitHub Actions.

## Ej i detta steg

Frontend-analysvyn "Näringslivets struktur", enkätjämförelse/viktning, kartor med enskilda arbetsställen, SNI 2007 → 2025-mappning.

## Tekniska detaljer

- Migration (unikt namn, t.ex. `0019_scb_afr`): `afr_code_tables` + `afr_code_table_history`, `afr_je_ident` (je_id ↔ peOrgNr/orgNr, endast admin-läsning, inga grants till anon/vanliga authenticated), `afr_sync_runs` (källdatum, hämtningstid, counts), `afr_je_current`, `afr_je_history`, `afr_je_sni_current`, `afr_je_sni_history` (kopplad till history_id), motsvarande för AE, samt staging för delta och första laddningen knutet till `etl_batches`. Index på län, kommun, SNI, anstKl, agKat, je_id. RLS på allt; läsning initialt bara admin. Seed av `data_sources` för `scb-afr`.
- Funktioner (security definer, grant endast till ETL-rollen, ingen generell DELETE): `afr_start_sync` (tar emot source_count, count före/efter, observerat antal), `afr_store_chunk` (checksumme-idempotent), `afr_finalize_sync` (balanskontroll och bortfallströskel), `afr_abort_sync`, `afr_current_hashes` (paginerad).
- Hash: SHA-256 över kanoniskt JSON av historiserade fält; beräknas i R och verifieras i databasen.
- Endpoints under `/api/public/jobs/afr/*` med befintlig ETL-nyckel, rate limit och Zod-validering; hash-endpointen svarar gzip. Återanvänder `etl-auth.server.ts` och batchmönstret.
- R: `R/etl/afr_*.R` (klient, normalisering, hash, delta, synk) via `etl_api.R`; workflow `.github/workflows/etl-scb-afr-daily.yml` (cron `0 4 * * *` + manuell körning med lägena `count-only`, `initial-load`, `daily`).
- Dokumentation i `docs/afr-etl.md` och regel i `AGENTS.md`.
