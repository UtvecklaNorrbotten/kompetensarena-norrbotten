# UKÄ – återuppta här

Senast uppdaterat: 2026-11-06. Repo `UtvecklaNorrbotten/kompetensarena-norrbotten`.
Arbetsgren `fix/uka-verified-checkpoint-import`, utkast PR #82.
Ingen merge eller produktionsimport har gjorts av denna utredning.

## Aktuellt genombrott – 2026-11-06

Körning **42217378947** passerade samtliga steg. Den nya studieform-först-kön har
**857 färdiga noder, 9 731 observationer, inga väntande och inga fel** för
Riket/Kvinnor/-24/2025-26. Återstarten behandlade 693 noder med 689 nya anrop;
redan färdiga noder hämtades inte om. Detta är en avslutad annonserad JSON-graf för ett urval,
inte en full produktionsimport.

Artefakt `uka-json-probe` ID **13502605500**, utgår 2026-11-20, är nu vald i konfigurationen.
Den innehåller färdig kö, källcache och den gamla blockerade kön.
Den gamla källkonflikten testas nu som en explicit förväntad spärr med noll anrop och
oförändrade noder. Nya fel i den nya hämtningen tillåts fortfarande stoppa jobbet.

Efterkontroll mot de 230 ordnade ämnesvägarna i UKÄ:s exportfilter:
**0 dubbletter, 0 ogiltiga ämnesvägar, 222 representerade ämnesvägar, 8 ej annonserade**.
De åtta saknade vägarna redovisas i `uka-hst-coverage-2026-11-06.json`; de får inte
omvandlas till nollor. Kontrollera kontrastprovet mot Total kön/ålder innan slutsatser dras.
De sparade ämnesvägarna bevarar den aktiva föräldravägen, även för återanvänd kod 1051.

Två extra LTU-anrop för oannonserade Övrigt-kombinationer gav HTTP 500.
Se `uka-absent-selection-probe-2026-11-06.json`: detta bevisar varken legitim tomhet eller noll.
Underlaget till UKÄ är uppdaterat men inte skickat.

Kontrastprov för de åtta saknade vägarna: Psykoterapi, Persiska och Koreografi
annonseras för Total kön/ålder 2025/26, med källvärden 282,8, 6,1 respektive 30,1.
De övriga fem saknas även i det övergripande urvalet. Detta skiljer ett populationsurval
från den generella filterlistan, men bevisar fortfarande inte att saknade rader betyder noll.
Se `uka-hst-missing-path-contrast-2026-11-06.json`.

Diagnostikändringar: JSON-workflowet avbryter inte längre en pågående källa vid nya commits.
Äldre CSV-/R-källprov körs endast vid manuell workflow_dispatch; PR behåller enhetstesterna.
Detta undviker upprepning av de redan dokumenterade CSV-felen vid varje commit.
Nya kontroller: `scripts/uka_hst_coverage.py` och fem tester.
Totalt passerar 51 lokala UKÄ-tester, varav 43 ingår i JSON-workflowet. Nästa steg är att verifiera
saknade urval, fler fullständiga kön/ålders-/periodurval och universiteten, därefter strategier
för övriga nio indikatorer och staging/publicering. Ingen merge eller produktionsimport.

## Tidigare delresultat (historik)

## Senaste återstartspunkt

Körning **42214430694**, artefakt `uka-json-probe` ID **13500557368**, utgår
2026-11-20. Konfigurationen pekar nu hit. Den innehåller båda köerna och källcachen.
Studieform-först-steget och alla 38 tester passerade i Actions. Den separata kön har
**104 färdiga noder, 2 105 observationer och 298 väntande**, inga fel; stopp efter 60 nya
anrop. Hela jobbet är fortfarande avsiktligt rött på den gamla all-routes-spärren.
Detta ska inte misstolkas som att det nya källprovet misslyckades eller är komplett.

Extra källprov: Riket 2016/17 ger Medicin/Övrigt 33,1 och Naturvetenskap/Övrigt 22,1
för Fristående kurser/Kvinnor/-24. För LTU 2025/26 annonseras ingen Övrigt-rad under
dessa två områden. Frånvaro i listan är **inte** i sig bevis för en verifierad tom observation.
Se `uka-study-first-additional-2026-11-06.json`. Inga totaler har räknats genom summering.

## Ny prövning: studieform först

Den alternativa strategin `study-first` väljer Studieform endast vid roten och går sedan
Ämnesområde → Ämnesdelområde → Ämnesgrupp. Ämnestotaler utan studieformsval hämtas via
rotens ämnesgrenar. Källtotaler summeras aldrig. Gamla `all-routes` är oförändrad standard;
strategier kan inte bytas i en existerande kö. Den permanent blockerade kön bevaras.

Verifierat 2026-11-06: Fristående kurser först ger rätt Övrigt-gren under både Medicin
(38,1 HST, medicinska ämnesgrupper) och Naturvetenskap (56,2 HST, naturvetenskapliga grupper).
Samtliga 48 observationsnycklar och värden för uni:171/Kvinnor/2025-26 över fyra åldrar
är identiska med full referenstraversering. Kontrollskript `scripts/uka_study_first_probe.py`
och `uka-study-first-evidence-2026-11-06.json` dokumenterar jämförelsen.

Lokalt större prov: separat `national-study-first.sqlite` nådde 54 färdiga noder,
1 199 observationer, 199 väntande och inga fel. Stoppet var en uttrycklig budget om
24 nya anrop. Detta bevisar ännu inte full ämnes-/lärosätestäckning. Kön finns i
`output/uka-conflict-42210008954/`, med samma snapshot 2026-11-06.
Workflowet prövar också strategin separat och sparar den nya kön i samma artefakt.
Enhetstester: 38 i den femdelade diagnostiksviten; 46 när samtliga test_uka*.py körs.

Nästa steg: återställ den senaste artefakten som innehåller `national-study-first.sqlite`,
återuppta just denna kö och verifiera full graf, källhierarki, universitetslistor samt flera
perioder/kön/åldrar. Att vägen fungerar för två Övrigt-grenar är inte bevis för att andra
kontextfel saknas. CSV-likvärdighet och fullständig produktionsimport är fortfarande overifierade.

## Tidigare spärr i all-routes – bevarat regressionstest

Senaste större körning **42210008954** stoppade korrekt vid en permanent källkontextkonflikt,
efter 41 färdiga noder och 1 038 sparade observationer. 211 noder återstår och en är blockerad.
Artefakt `uka-json-probe`, ID **13497844492**, innehåller både kön och det utlösande källsvaret.
`config/uka_json_diagnostic_checkpoint.json` pekar nu på denna blockerade artefakt för att bevara
bevisen och undvika nya hämtningar av samma material. Ett rött källjobb är här avsiktligt.

Verifierad källdetalj: koden **1051 / Övrigt** återanvänds under både
914 (Medicin och odontologi) och 915 (Naturvetenskap) i exportfiltren.
JSON-noden för den medicinska grenen annonserar två Fristående kurser-rader med samma etikett,
värden **38,1** och **56,2**, och olika sluggar. Direkta anrop visar att 38,1-länken har medicinska
ämnesgrupper medan 56,2-länken har naturvetenskapliga ämnesgrupper.
Det räcker alltså inte att URL:ens kön/ålder/år är kvar och att barnvärdet matchar det annonserade värdet.
Även ämnesgrenens kontext måste verifieras.

Se `uka-source-context-conflict-2026-11-06.json` för exakta länkar, värden och ämnen.
Metadata-parser version 2 bevarar båda föräldraplaceringarna; version 1 skrev över den första.
Detta är ingen generell lösning på JSON-kontextproblemet. Slå inte ihop olika sluggar,
summera inte de dubbla etiketterna och ge dem inte nya produktionsnycklar för att kringgå stoppet.
Nästa utredning gäller fullständig källkontext/identifierare eller ett korrigerat bulkuttag från UKÄ.
Det är fortfarande inte visat att detta också orsakar CSV-tjänstens nollbytefiler.

Kömotorn gör nu **0 nya anrop** om en permanent felaktig nod redan finns, även om andra noder väntar.
Tillfälliga fel kan återförsökas, högst tre gånger med väntetid; datakonflikter förblir blockerade.
Senaste testuppsättningen omfattar 35 enhetstester. Felunderlaget till UKÄ har kompletterats men inte skickats.

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
Använd den i checkpointfilen utpekade artefakten på PR #82; den kan vara avsiktligt blockerad och ska då inte startas om blint.
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
