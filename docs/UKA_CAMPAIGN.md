> **Aktuell fortsättning 2026-11-10:** PR #82 är mergad. Se [UKA_COVERAGE.md](UKA_COVERAGE.md) för den nya kontrollpunkten för alla tio indikatorer i PR #84, exakta dimensioner, verifierade uttag och kvarvarande produktionskrav. Nedanstående daterade uppgifter bevaras som historik.

# UKÄ – tioårskampanj och filbaserad staging

Denna del hämtar och kontrollerar källobservationer. Den ansluter inte till appens databas
eller publicerings-API. `publish_allowed` är alltid false, även när alla hämtningar är färdiga.

## Fryst körplan

Planen skapas från `docs/uka-source-inventory-2026-11-06.json`. Varje del är ett unikt
urval av indikator, period, kön och ålder, med Riket som rot och källans lärosäteslistor.
API:ts egna totaler väljs genom att totalfiltret utelämnas; inga totalvärden summeras.

| API-ID | Planerade urval |
|---|---:|
| 13 | 240 |
| 31 | 240 |
| 33 | 120 |
| 97 | 240 |
| 99 | 60 |
| 108 | 120 |
| 136 | 15 |
| 77 | 30 |
| 134 | 120 |
| 135 | 120 |
| Summa | 1 305 |

Perioderna omfattar tio års källhistorik där den erbjuds. Indikator 136 erbjuder bara fem
valda år. Upptäckt görs separat per period: program som finns historiskt kan saknas i
senaste periodens lista, vilket verifierats för indikator 135.

Manifestet låser plan-ID, urval, snapshot, indikatorpolicy och, för HST, ämneshierarkin.
Ändrad plan eller policy får inte återuppta samma stagingdatabas.

## Jobb och återstart

`.github/workflows/uka-staging.yml` kör en vald indikator per manuell körning
(33 som förval); PR-kontrollen kör endast 33. Den globala planen ovan bevaras.
Varje jobb har både anropsbudget och tidsbudget. En budgetgräns pausar hämtningen;
den betyder inte att datamängden är komplett.

`config/uka_staging_campaign.json` anger:

- `source_run`: en fryst gemensam bas med tidigare verifierade källsvar och köer.
- `resume_run`: senaste stagingkörningen med en artefakt för var och en av de tio indikatorerna.
- Budgetarna styr hur långt nästa körning får fortsätta. Noll nya anrop används för återstartskontroll.

Gemensamma källsvar läses från basen och kopieras inte till varje indikators artefakt.
Indikatorns artefakt innehåller bara egna nya svar, egna köer, stagingdatabas och manifest.
Både basen och stagingartefakterna sparas i 30 dagar. Artefaktkedjan måste finnas kvar;
saknad återstartspunkt är ett fel, inte tillstånd att börja om med nya tunga anrop.

Tidigare färdiga, matchande köer kan återanvändas som startpunkt. Samma urval, snapshot,
strategi och indikatorpolicy krävs. Ofärdiga eller blockerade basgrafer återanvänds inte
som färdiga. Hämtningar som redan är klara i kampanjen körs inte om.

## När ett urval får gå till staging

Alla noder i urvalets graf måste vara färdiga. Därefter läses de oförändrade källsvaren
från cache med **noll nätverksbudget**. Varje observationsvärde, lärosäte och källhash
jämförs igen. HST:s ämnesvägar måste även passa den frysta källhierarkin.

Observationer och urvalets färdigmarkering skrivs i en enda SQLite-transaktion. Ett avbrott
före commit lämnar ingen halvfärdig staging. Den redan hämtade källkön finns kvar och
kan användas igen utan nya API-anrop. Varje färdigt urval får en kontrollsumma över sina
stagingrader, som kontrolleras vid återstart. En ändrad färdig rad stoppar återstarten.

En observationsnyckel omfattar indikator, period, kön, ålder, lärosäte och hela dimensionsvägen.
Dubbletter stoppas. Decimalvärden behåller källans värde; inga värden avrundas
eller summeras. Uttryckligt null bevaras och skiljs från saknat värdefält.

## Fel och rapportering

Ett tekniskt fel får aldrig bli ett legitimt tomt urval. Kömotorns väntetid och högst tre
försök över återstarter gäller tillfälliga fel. Okända dimensioner och värdekonflikter blockeras.
Andra indikatorer och andra urval kan ändå fortsätta inom sina budgetar.

`campaign-report.json` visar färdiga och planerade urval samt observationer som faktiskt sparats i staging.
Ofullständiga köers observationer räknas separat och är inte tillåtna i staging.
Rapporten redovisar period, kön, ålder och lärosäteskoder per färdigt urval.
GitHub kontrollerar rapportens plan och snapshot för vald indikator.

Uppdatering 2026-11-09: workflowet kontrollerar nu den enda valda indikatorns
rapport. HST har dessutom separat pakettäckning i `csv_packages` och
`csv_observations` i samma SQLite-databas. Paketets färdigmarkering och rader
skrivs atomiskt efter exakt källjämförelse, utan att färdigmarkera ett nationellt
jobb. Paketrader kan överlappa nationella observationer och ska inte summeras
med dem. Manifest och radkontrollsummor kontrolleras vid återstart.
Se [HST:s aktuella kontrollpunkt](uka-indicator-33.md).

## Vad som återstår före publicering

Alla planerade hämtningar måste bli färdiga och källtäckningen måste verifieras, inklusive
legitima tomma urval, lärosäten och revisioner. Ett datum som snapshotnamn är inte bevis
för en oförändrad källversion. Dessa spärrar förblir uttryckliga även efter en grön körning.

Appens batch-API behöver fortfarande stabil importnyckel, progress/status, verifierat manifest,
återstartbara uppladdningar samt skydd för föregående publicerade snapshot. Den befintliga
publiceringsvägen används inte av denna kod. Ingen produktionsimport eller migration är gjord.
