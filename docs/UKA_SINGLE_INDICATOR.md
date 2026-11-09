# UKÄ – en indikator per chatt

Kontrollerat 2026-11-09 mot PR #82 och funktionscommit `38c729a10b4cd302e2d2d08bc99cf2fc282747a3`.
Repo: UtvecklaNorrbotten/kompetensarena-norrbotten.
Arbetsgren: `fix/uka-verified-checkpoint-import`. PR #82 är öppen, draft och inte mergad.

## Vad denna kontroll omfattar

Repots dokumentation, indikatorregister, kampanjkonfiguration, workflow och GitHubs metadata för körningar/artefakter.
Inga nya UKÄ-anrop, testkörningar, databasändringar eller produktionsimporter gjordes.
Stagingantal nedan är från den sparade rapporten 2026-11-06, inte en ny inventering av UKÄ.
Artefakternas existens och giltighetstid kontrollerades via GitHub; deras innehåll laddades inte ner och kontrollsummorna räknades inte om här.

Senaste dokumenterade funktionscommit har lyckad stagingkörning 42251266043, verifierad via GitHub.
84 tester rapporteras i PR/dokumentation; de kördes inte om i denna kontroll.
48/1 305 planerade urval och 25 342 observationer finns enligt sparad stagingrapport.
Grön körning betyder inte komplett datatäckning. Ingen indikator är färdig för produktion.

## Fast återstartspunkt

- Snapshot/manifest: `2026-11-06`. Datumet är inte en verifierad källversion.
- Gemensam källbas: run `42227843941`, artefakt `uka-json-probe`, ID `13506706544`.
- Stagingåterstart: run `42242045989`, artefakt `uka-staging-<API-ID>`.
- Basen och alla tio stagingartefakter finns och är inte utgångna enligt GitHub 2026-11-09; angivet utgångsdatum 2026-12-06.
- Nuvarande kampanjbudget: 0 nya anrop per indikator, 150 sekunder, högst 50 jobb.
- Återställ endast vald indikators staging samt den gemensamma bas som den behöver.
- Verifiera manifest och kontrollsummor före fortsatt arbete.
- Bevara snapshot, policy och manifest i befintliga köer. Ändringar kräver separat kampanj.
- Nya källsvar får inte antas tillhöra samma källversion bara för att snapshotdatumet behålls; kontrollera revisioner och dokumentera osäkerheten.

## Indikatorer

Namn från `R/etl/uka_sync.R`; antal från `docs/uka-staging-progress-2026-11-06.json`.
Ordningen nedan är rekommenderad arbetsordning, inte ett påstående om tidigare prioritering.

| Ordning | API-ID | Indikator | Färdiga/planerade urval | Stagingobservationer |
|---|---:|---|---:|---:|
| 1 | 33 | Helårsstudenter (HST) | 1/120 | 9 731 |
| 2 | 99 | Söktryck till yrkesexamensprogram | 3/60 | 1 337 |
| 3 | 97 | Antagna till yrkesexamensprogram | 3/240 | 1 266 |
| 4 | 13 | Förstahandssökande till yrkesexamensprogram | 3/240 | 1 281 |
| 5 | 31 | Nybörjare på yrkesexamensprogram | 4/240 | 895 |
| 6 | 108 | Examinerade | 2/120 | 2 048 |
| 7 | 136 | Etablering på arbetsmarknaden | 2/15 | 1 336 |
| 8 | 77 | Kvarvaro termin 3 för högskolenybörjare | 8/30 | 3 997 |
| 9 | 134 | Kvarvaro termin 3 på program | 3/120 | 1 445 |
| 10 | 135 | Examensfrekvens på program | 19/120 | 2 006 |

HST väljs först eftersom CSV-/JSON-likvärdighet och skydd mot ofullständig CSV-staging har mest referensunderlag.
99 och 97 har vardera en verifierad CSV-/JSON-jämförelse med 66 observationer i ett avgränsat urval.
Detta innebär inte verifierad täckning för andra perioder, kön, åldrar eller lärosäten.

## Första chatten: endast HST (33)

Mål: kartlägg kvarstående dimensioner/kombinationer och anslut verifierade CSV-paket till återstartbar staging för indikator 33 med positiva täckningskontroller.
Börja med ett avgränsat paket och offlineåterspelning, inte hela tioårshämtningen.

Läs först:
1. Denna fil.
2. `docs/UKA_CAMPAIGN.md` (89 rader vid kontrollen).
3. `docs/uka-csv-bulk-evidence-2026-11-06.json`.
4. `docs/uka-csv-staging-audit-2026-11-06.json`.
5. Endast indikator 33 i `docs/uka-source-inventory-2026-11-06.json`.

Läs vid behov:
- `scripts/uka_csv_bulk_probe.py`, `scripts/uka_csv_staging_audit.py`, `scripts/uka_campaign.py` och relevanta tester.
- `docs/uka-independent-hst-reference-2026-11-06.json`.
- Sök relevanta avsnitt i äldre utredning; läs inte automatiskt hela `UKA_RESTART.md` eller `uka-import-investigation.md`.

Verifierat underlag:
- Sju CSV-exporter för Riket/LTU/uni:171; gemensamma uttag matchar separata uttag:
  14 705 observationer 2025/26 och 14 975 observationer 2016/17.
- Frysta CSV-filer/metadata/kvitton: `tests/fixtures/uka-hst-bulk-2026-11-06.zip`.
- Nationellt avslutat JSON-urval Kvinnor/-24/2025-26: 9 731 stagingobservationer.
- CSV-deluttag har 1 235 identiska överlappande observationer men saknar 8 496 nationella referensobservationer.
  Deluttaget får inte färdigmarkera det nationella urvalet.
- Ämnesidentitet måste behålla hela föräldravägen; etiketten Övrigt återanvänds.
- Totaler hämtas från källan och får aldrig konstrueras genom summering.

Kvar:
- Skrivande CSV-importör med manifest-, värde-, dubblett- och täckningsspärrar.
- Verifierad täckning per period, lärosäte, kön och ålder.
- Legitima tomma urval, sekretess/null och revisioner/källversion.
- Ett tekniskt nollbytes-/500-svar är inte bevis för tom data eller nollvärde.

## Regler för varje arbetsomgång

- Endast en indikator och ett tydligt delmål åt gången. Kör chattar sekventiellt på denna gemensamma gren.
- Börja med sparade svar och offlinekontroller. Visa inte stora råsvar, datatabeller eller loggar i chatten.
- Begränsa nya prov till små block med angiven anrops- och tidsbudget; spara kontrollpunkt mellan block.
- Skriv resultat i `docs/uka-indicator-<API-ID>.md`: verifierat, belägg, osäkert, kod/teststatus och exakt nästa åtgärd.
- Länka detaljerade underlag i stället för att duplicera dem. Bevara tidigare belägg.
- Vid start: läs aktuell PR/gren och vald indikators statusfil om den finns; denna kontroll är en daterad utgångspunkt.
- Starta inte nuvarande `uka-staging.yml` i tron att det väljer en indikator: workflow_dispatch saknar indikatorval och matrisen kör alla tio.
  Använd avgränsad lokal CLI eller inför och verifiera uttryckligt indikatorval innan manuell körning.
- Indikator 108 kräver Inriktning. Indikator 135 kräver periodvis programupptäckt; senaste periodens programlista räcker inte historiskt.
- Ingen merge, migration eller produktionspublicering ingår i indikatorchattens arbete.
- Avsluta med länk till statusfilen och en kort överlämning. Starta inte nästa indikator automatiskt.

## Gemensamma krav som gäller alla indikatorer

Alla svenska lärosäten samt Riket; tio års historik där den finns; alla källans åldrar.
Kvinnor/Män/källans Total bevaras där uppdelningen finns. Endast teknisk Total lagras utan könsdimension.
Inventeringen erbjuder fem år för 136; det är inte bevis för att äldre data generellt saknas.
Filteralternativ är inte bevis för att alla kombinationer finns som observationer.
Ofullständiga uttag får inte ersätta publicerad statistik.
Backendens återstartbara uppladdning, serverkontrollerade manifest och bevarad föregående publicering återstår som separat integrationsarbete.
