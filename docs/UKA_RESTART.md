# UKÄ – återuppta här

Senast uppdaterat: 2026-11-06. Repo `UtvecklaNorrbotten/kompetensarena-norrbotten`.
Arbetsgren `fix/uka-verified-checkpoint-import`, utkast PR #82.
Ingen merge eller produktionsimport har gjorts av denna utredning.

## Auktorisation och krav

Användaren har godkänt granskning, diagnostik, arbetsgrenar och PR.
Merge och produktionsimport är godkända först när hela lösningen är verifierad.
Alla tio indikatorer: 13, 31, 33, 97, 99, 108, 136, 77, 134, 135.
Alla svenska lärosäten plus Riket, tio års historik där den finns, alla källans åldrar,
Kvinnor/Män/UKÄ:s egen Total. Totaler får aldrig konstrueras genom summering.
Ofullständiga uttag får inte ersätta publicerad statistik. Felunderlaget till UKÄ är förberett men inte skickat.

## Verifierat – gör inte om dessa undersökningar

- CSV-export ger nollbytefiler även i UKÄ:s riktiga webbformulär för minimala HST-uttag av Riket 2025/26 och 2024/25.
- R- och Python-klienter reproducerar felet. Intern orsak/cachepåverkan är okänd.
- JSON ger källtotaler för senaste och äldsta valda period för alla tio indikatorer.
- Sex HST-stickprov samt 12 kön/ålderskombinationer för uni:171 passerar.
- Hela annonserade JSON-grafen för uni:171, Kvinnor, 2025/26, fyra åldrar: 48 unika observationer, inga dubbla nycklar. Två ordningar ger identiska nycklar/värden; andra ordningen gör inga nya anrop.
- GitHub-körning 42197119005 passerade 19 tester och källproven på commit `a3c3f694b59b3c7cd9a0c1857e348c349ff0066c`.
- Ett slutet annonserat JSON-träd bevisar inte att alla databasobservationer exponeras. CSV-likvärdighet är fortfarande overifierad.

Detaljer: `uka-import-investigation.md`, `uka-json-probe-2026-11-06.json`,
`uka-hst-complete-2026-11-06.json`, `uka-export-felunderlag-2026-11-06.md`.

## Hämtningsplanen

`scripts/uka_json_plan.py` bygger en deterministisk plan för alla tio indikatorer utan nätverksanrop.
Varje rotjobb representerar indikator/period/kön/ålder med Riket som ingång.
Lärosätesvärden läses ur Rikets gruppsvar; multiplicera inte anropsantalet blint med antalet lärosäten.
Planen skiljer validerat rotsvar från färdig underliggande graf. En cachad rot är aldrig en färdig import.
Jobb-ID binder strategi, urval, filterinventering och snapshot-ID. Snapshot-ID är inte en verifierad källversion.
Sammanfattning finns i `uka-json-plan-2026-11-06.json`. Full plan kan återskapas:

```bash
python -m pip install requests beautifulsoup4
python scripts/uka_json_plan.py --snapshot 2026-11-06
python -m unittest discover -s tests -p test_uka_json_plan.py -v
```

Återanvänd diagnostikartefakten `uka-json-probe` från körning **42197119005**
(sparad till omkring 20 november). Lägg innehållet i `output/uka-json-probe` om den lokala cachen saknas.
Verifiera alltid checksumma och urval innan återanvändning. Efter utgångsdatum får nödvändiga svar hämtas om med begränsad anropsbudget.

## Nästa konkreta implementation

1. Kömotorn är nu implementerad i `scripts/uka_json_queue.py` för HST. SQLite sparar nodvärde, källa-hash, barnlänkar, observationer och status atomiskt. Enbart ej färdiga noder bearbetas vid återstart. Skrivarlås förhindrar samtidiga arbetare i samma kö.
2. Åtta nya tester verifierar avbrott/återstart, identiska slutvärden, inga omhämtningar av färdiga noder, rollback av halva checkpoints, budgetstopp, källvärdeskonflikter, saknade värdefält, snapshot-konflikt och skrivarlås. Tidsbudgeten kontrolleras mellan anrop; ett pågående HTTP-anrop kan överskrida den.
3. Ett nationellt HST-rotjobb (2025/26, Kvinnor, -24) har startats kontrollerat: lokalt 6 godkända noder, 199 observationer, 51 väntande noder efter budgetstopp. Först användes bara sparade svar, sedan 4 nya anrop före tidsstopp. Detta är inte en komplett nationell datamängd. Se `uka-queue-checkpoint-2026-11-06.json`.
4. Återanvänd källans tidsserier där det är bevisat korrekt, men upptäck historiska grupper per period. Senaste årets ämnen/lärosäten räcker inte för historisk täckning.
5. Lös oberoende referens, legitima tomma/saknade/sekretessvärden och källversion/revision innan full import.
6. Implementera därefter UKÄ:s databas-resume/progress och manifestspärrar, samt återläsning efter publicering. Nuvarande UKÄ-abort raderar staging; ändra inte detta oprövat i produktion.

Den konservativa HST-gränsen 138 600 gruppanrop är en planeringsgräns, inte ett uppmätt behov.
Starta inte den stora tioårshämtningen för att bara få gröna jobb. Inga nya tillstånd behöver begäras för diagnostik inom denna avgränsning.

## Återuppta nodkön efter pausen

JSON-workflowet sparar nu även SQLite-kön och källcachen i artefakten `uka-json-probe`.
Använd senaste godkända körningen på PR #82, eftersom äldre körningar saknar köfilen.
Återställ hela artefakten till `output/uka-json-probe`; generera inte en ny tom kö ovanpå den sparade.
Kön binder exakt urval och snapshot. Fortsätt med samma snapshot-ID som körningen använde.

```bash
python scripts/uka_json_queue.py \
  --root-url 'https://statistik-api.uka.se/api/totals/33?university=1&year=2025%2F26&gender=Kvinnor&age_group=8' \
  --snapshot 2026-11-06 \
  --database output/uka-json-probe/national-queue.sqlite \
  --max-new-requests 10 --max-nodes 20 --seconds 30
```

`request_budget`, `node_budget` och `time_budget` är avsiktliga stopp som bevarar kön.
`source_error` stoppar fortsatt behandling och sparar nodens fel; fel ska undersökas, inte klassas som legitim tom statistik.
`graph_closed` betyder bara att denna annonserade JSON-graf är uttömd. Publiceringsflaggan är alltid falsk.

Nästa återstående kodsteg: verifiera kömotorn mot fler nationella HST-noder, testa återläsning av sparade observationer mot direktuttag,
bygg ett kampanjlager över rotjobben och pröva selektiva återförsök i en större kontrollerad körning.
Övriga nio indikatorers dimensioner stöds ännu inte av denna HST-kömotor.
Källrevisioner och oberoende fullständighetsreferens blockerar fortfarande produktion.

Källdetalj verifierad under kötestet: UKÄ utelämnar `groups` i vissa institutionsspecifika slutnoder. Kömotorn accepterar detta endast när ämnesområde, delområde, ämnesgrupp och studieform redan är valda och källans periodvärde verifieras. Saknad struktur i rotnoder eller nationella noder förblir ett fel. Regressionstester täcker båda fallen.

## Selektiva återförsök och verifierad artefaktåterstart

Kömotorn skiljer nu tillfälliga transportfel från datakonflikter. Timeout/anslutningsavbrott
och HTTP 408/425/429/500/502/503/504 får högst tre misslyckade försök per nod,
med 30 och 60 sekunders väntetid före nästa försök. Certifikatfel, andra HTTP-fel,
felaktiga observationer och struktur-/värdekonflikter öppnas aldrig automatiskt igen.
Försöksräknare och tidpunkt sparas i SQLite, även över avbrott och processbyten.

Status `retry_wait` innebär att grafen inte är klar. CLI avslutar med kod 75 så att GitHub
redovisar ett tekniskt avbrott och ändå sparar artefakten. Nästa körning försöker bara om
förfallna tillfälliga fel. Efter tre misslyckanden blir noden blockerad (`transient_exhausted`).
Ingen blockerad datakonflikt får återöppnas bara för att få en grön körning.

Den verifierade GitHub-artefakten från **42202630673** har faktiskt laddats ner och dess
SQLite-kö återställts: 13 färdiga noder och 416 observationer. Lokal fortsättning gav
22 färdiga noder, 642 observationer och 146 väntande noder efter 8 nya anrop.
SQLite-integriteten är OK, inga dubbla observationsnycklar finns och tidigare färdiga
noder behölls. Se `uka-queue-retry-2026-11-06.json`.

Workflowets standardåterstart definieras nu i `config/uka_json_diagnostic_checkpoint.json`.
Det laddar ner den kända artefakten före planeringen, så grundproven behöver inte hämtas om.
För att fortsätta från en NYARE lyckad körning: ange dess `resume_run` och ursprungliga
`snapshot` vid manuell start, eller uppdatera checkpointfilen i arbetsgrenen.
Ett uttryckligt run-ID utan snapshot avvisas; en utgången artefakt ger fel, inte en tyst omstart.
Den nationella fortsättningen har högst 60 nya anrop, 100 noder och 120 sekunders budget
per körning. Detta gäller ett enda rotjobb, inte hela tioårshämtningen.

Fyra nya tester verifierar felklassificering, beständig väntetid, tre-försöksgränsen
och att datakonflikter förblir blockerade. Totalt finns 34 tester i JSON-workflowet.
Det nationella urvalet är fortfarande ofullständigt och publicering är fortsatt spärrad.
