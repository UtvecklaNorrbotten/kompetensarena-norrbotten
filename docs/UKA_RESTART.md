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

1. Bygg en beständig kö per rotjobb med annonserade barnlänkar, kanonisk URL/dimensionsnyckel, status, källa-hash och felorsak. Spara varje godkänt steg atomiskt, inte bara en färdig graf.
2. Lägg in global tids-/anropsbudget och återstart som enbart bearbetar ej färdiga noder. Testa avbrott mitt i en graf.
3. Börja med ett nationellt HST-rotjobb. Mät verkliga noder, lärosätestäckning och värden innan fler perioder/kön/åldrar läggs till. Bevara hela källtotalen separat.
4. Återanvänd källans tidsserier där det är bevisat korrekt, men upptäck historiska grupper per period. Senaste årets ämnen/lärosäten räcker inte för historisk täckning.
5. Lös oberoende referens, legitima tomma/saknade/sekretessvärden och källversion/revision innan full import.
6. Implementera därefter UKÄ:s databas-resume/progress och manifestspärrar, samt återläsning efter publicering. Nuvarande UKÄ-abort raderar staging; ändra inte detta oprövat i produktion.

Den konservativa HST-gränsen 138 600 gruppanrop är en planeringsgräns, inte ett uppmätt behov.
Starta inte den stora tioårshämtningen för att bara få gröna jobb. Inga nya tillstånd behöver begäras för diagnostik inom denna avgränsning.
