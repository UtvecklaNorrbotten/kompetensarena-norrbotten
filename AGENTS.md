<!-- LOVABLE:BEGIN -->
> [!IMPORTANT]
> This project is connected to [Lovable](https://lovable.dev). Avoid rewriting
> published git history — force pushing, or rebasing/amending/squashing commits
> that are already pushed — as it rewrites history on Lovable's side and the
> user will likely lose their project history.
>
> Commits you push to the connected branch sync back to Lovable and show up in
> the editor, so keep the branch in a working state.
<!-- LOVABLE:END -->

## Arkitekturregler
- Adminvyer ligger under `/admin/*`, är `ssr: false`, finns inte i navigation.ts och läser via serverfunktioner med `requireSupabaseAuth` + `has_role(admin)`; varför: ett enda behörighetssystem (user_roles) och inget adminläckage i publik SSR.
- Datakällestatus härleds generellt ur `data_source_runs` (via `source_id`) med `data_source_state` som reserv; varför: inga källspecifika villkor i UI när nya källor tillkommer.

- Områdessidor och etiketter definieras i `src/config/areas.ts`; nya sidor ska ha egen sidtitel, och platshållare får aldrig se ut som uppmätta resultat.
- Publik sökning indexerar bara innehåll som får publiceras. Råa enkätsvar, personuppgifter och arbetsgivarnivå får inte läggas i `search_index`.
- Enkätimport ska först valideras mot en faktisk kodad fil. Publicering ska ske atomiskt, och arbetsgivarsvar kräver både RLS och serverkontroll innan en vy byggs.
- AFR (SCB företagsregister) synkas av GitHub Actions via nyckelskyddade `/api/public/jobs/afr/*` och `afr_*`-funktioner; ETL skickar bara delta efter fullständig traversering och databasen balanskontrollerar före atomisk finalisering, identifierare finns bara i `afr_je_ident`; varför: korrekt historik utan dagliga fullkopior och utan att röja fysiska personer.
- AFR-SNI lagras hybrid: aktuell SNI i långt format (`afr_*_sni_current`) + `primary_sni` på current, historisk SNI som kanoniskt JSONB-snapshot (`sni`) på historikraden; `afr_*_sni_history` är avvecklade; varför: snabb analys av aktuell SNI utan miljontals historiska radkopplingar, exakt rekonstruktion ändå möjlig.
- Visualiseringar läser förberäknade `agg_*`-tabeller (Riket, alla län, alla kommuner där källan har dem) via `src/lib/aggregates.functions.ts`, aldrig råa `observations`/`afr_*`; aggregaten räknas om timvis av `agg_refresh_due()` när källans markör (aktiv batch/AFR-källdatum) ändrats; varför: snabba svar utan att ETL eller HTTP-gränser påverkas.
- Geografiskt förval för visualiseringar definieras i `src/config/geo.ts` och bärs i URL:en (`?geo=`); varför: delbara länkar och ett ställe att ändra förvalet.
- Verified UKÄ snapshot imports use per-indicator `uka*_verified_*` functions bound to a manifest (chunk hashes, coverage) in `uka_verified_imports`, activate atomically and retain the previous batch; legacy `uka_store_chunk`/`uka_finalize_batch`/`uka_abort_batch` refuse (SQLSTATE 55000, HTTP 409) any indicator with a verified import; why: publish frozen staging packages with rollback that legacy ETL cannot overwrite or delete.
- The eight CSV-staged UKÄ indicators (13, 31, 97, 108, 136, 77, 134, 135) publish only through the shared `uka_snapshot_*` path (copy of an exactly fingerprint-matched active batch, or hash-bound canonical-line upload), driven by `scripts/uka_snapshot_publish_verified.py` with a frozen per-period manifest; its applied schema is recorded in `drizzle/uka_snapshot_verified_import.applied.sql` (not journaled, never re-apply); why: one audited, resumable, rollback-preserving path without moving raw data.
- The Education page reads a per-university catalog plus per-figure slices (one breakdown and selection, page-bounded) via `uka_education_catalog`/`uka_education_slice`, never a whole university in one response; why: Riket exceeds the server-function response limit.
- App icon imports go through `src/components/icons.ts`, which maps semantic names to official Nucleo Essential packages and explicitly lists unsupported fallbacks; this keeps licensing provenance clear and future library changes centralized.

- AFR names/addresses use admin-only `afr_profile_versions` plus latest-only contacts in `afr_profile_current`; canonical core hashes/history remain unchanged. Annual accounts use protected `company_accounts_latest` pointers and private content-addressed ZIP sources, never group facts as company values. See `docs/company-data/README.md`.

- RMI U3 läses som versionshanterade, förberäknade publika SCB-aggregat i `src/data/rmi`, via `aggregates.functions.ts` och `rmi.functions.ts`; ett begränsat svar per geografi/kön. Workflowet `etl-rmi-u3.yml` kontrollerar SCB:s metadata veckovis och hämtar om kvartalsvis. Se `docs/lan-kommun.md`. Inga råobservationer eller personuppgifter ingår.

- Arbetslöshetens publika läsmodell i `src/data/af` förberäknas från samma AF-arbetsböcker som månads-ETL:n. Läs den via `aggregates.functions.ts` med en geografi/kön eller månad/grupp per svar. BAS-filens egna SOK/AK-par används för andelar; rikstäljaren inkluderar restkategorin utan geografi. Se `docs/arbetsloshet.md`.

- Efterfrågan på arbetskraft läser förberäknade AF-aggregat via `labour-demand.functions.ts`, exporterat genom `aggregates.functions.ts`. Komprimerade geografifiler ligger i `public/data/demand` och läses via ASSETS-bindningen för att hålla Worker-koden liten; katalog och LoR-källsvar ligger i `src/data/demand`. Yrkesfilens KVAR hålls skilt från den långa platsserien. Se `docs/efterfragan-pa-arbetskraft.md`.

- Sysselsättning läser versionshanterade offentliga SCB-aggregat via `employment.functions.ts`, exporterat genom `aggregates.functions.ts`; hashade komprimerade geografi-/periodfiler i `public/data/employment` läses via ASSETS. BAS månadsdata, BAS årligt register och RAMS före/efter 2019 är separata serier. Se `docs/sysselsattning.md`; ingen läsning av råa observationer och ingen länkning över metodbrott.

- Matchning läser offentliga E3-aggregat via `matching.functions.ts` och `aggregates.functions.ts`, med hashade komprimerade filer i `public/data/matching` via ASSETS. Använd SCB:s publicerade andelar; räkna inte om dem från CKM-justerade antal. Utbildningsgrupp, nivå och inriktning har skilda totaler. Se `docs/matchning.md`.

- Arbetskraft läser versionshanterade publika SCB-aggregat via `workforce.functions.ts` och `aggregates.functions.ts`, med hashade geografi-/periodfiler i `public/data/workforce` via ASSETS. BAS arbetskraft, RMI U1b, U4 och anställda i yrkesregistret är olika populationer. Regionalt saknade bransch-/åldersuppgifter får inte ersättas tyst av riksvärden. Se `docs/arbetskraft.md`.
