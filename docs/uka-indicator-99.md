# UKÄ 99 – Söktryck till yrkesexamensprogram

> Produktionspublicerad 2026-11-10 efter uttryckligt godkännande, med oförändrade
> granskningsflaggor. Grund, batch-id och verifiering: [uka-99-publication-2026-11-10.md](uka-99-publication-2026-11-10.md).
> Avsnitten nedan beskriver insamlingen före publiceringen.

## Kontrollpunkt 2026-11-10

Gren `fix/uka-verified-checkpoint-import`, PR #82 öppen draft, bas för arbetet
`1f4a8e2455109432d9032d6fc223a7d8777df904`. Repots AGENTS.md är kontrollerad.
Ingen merge, migration eller produktionspublicering ingår.

## Definition och erbjudna dimensioner

UKÄ:s beskrivning: antal behöriga förstahandssökande per antagen, oavsett
tidigare högskolestudier. Antagna behöver inte ha programmet som förstahandsval;
söktryck kan understiga 1. Källa:
https://www.uka.se/statistik-och-analys/hogskolan-i-siffror/beskrivningar-av-statistiken/utbildning-pa-grundniva-och-avancerad-niva
(avsnitt Söktryck till yrkesprogram, kontrollerat 2026-11-10).

Färska exportmetadata: 81 lärosätesalternativ inklusive Riket, 78 programval
inklusive Total, Kvinnor/Män/Total. Ålder erbjuder **endast Total**; detta är
teknisk frånvaro av åldersuppdelning, inte en uppmätt ålderskategori.
Senaste tio kalenderåren: VT2017–HT2026, 20 separata terminer.
Samtliga erbjudna lärosäten/program begärs uttryckligen varje termin.
Faktiskt observerade alternativ och positiva JSON-listor sparas periodvis;
metadataalternativ är inte belägg för en observation i varje kombination.

CSV:s värdetext (t.ex. `2,30`) bevaras i råfil; staging använder Decimal-baserad
kanonisering till text (t.ex. `2.3`). Inga heltalsavrundningar, summeringar eller
medelvärden görs. Källans totalrader hämtas direkt. Tomma/sekretessmarkörer
bevaras; tekniska fel och frånvaro ger aldrig nya nollvärden.

## Återställt äldre underlag

- Gemensam JSON-bas: run 42227843941, artefakt 13506706544.
- Endast staging 99: run 42242045989, artefakt 13516211452.
- Återspelning: 0 nya anrop, 3 avslutade urval, 1 337 observationer,
  SHA-256 `e626360d2b115af9cf021f6ea6146e83380a0776681861858920a975f2e3bb0b`.
- Ursprunglig CSV återhämtad från det sparade käll-URL:et och verifierad mot
  `7ee405b3029cbd5091103e61b4d31f14a75c25421c4ed9a4b0e8b2a128a83ae0`.
- 66/66 exakta observationer återverifierade: Riket/LTU, HT2026, Total kön/ålder.
- Hela äldre stagingen matchar ny HT2026-CSV: 1 337/1 337 identiteter och värden.
  Detta verifierar det urvalets revisionsstabilitet, inte en officiell källversion.
  Se `uka-99-revision-check-2026-11-10.json`.

## Metod och budget

Ny fryst kampanj `2026-11-10` hålls separat från 2026-11-06.
Gemensamma Source/Probe/Decimal-/hash-/jämförelsefunktioner återanvänds;
indikatorns platta programdimension och avsaknad av åldersuppdelning valideras
uttryckligen i `uka_99_values.py` och `uka_99_full_csv.py`.

Per termin: högst 5 CSV-exporter (högst 10 HTTP-anrop för export/nedladdning),
4 JSON-anrop, 240 sekunder för blocket. Ingen automatisk retry. Metadata-
upptäckten använde 5 endpointanrop; ett första JSON-rotsvar sparades separat.
Varje termin jämförs exakt mot två disjunkta lärosätesuttag och två disjunkta
programuttag. Tre nationella könsrotsvar kontrollerar källtotaler, annonserade
lärosätesvärden och programvärden samt deras faktiska listor. Ett separat
Total-rotsvar kontrollerar stabilitet. Varje källsvar/CSV har kvitto och hash.
Staging skrivs atomiskt först efter godkända kontroller. Manifest, staging,
kvitton, råfiler och JSON-kontroller valideras på nytt vid återstart.

## Slutkontrollpunkt

Alla 20 terminer VT2017–HT2026 är färdiga i separat staging: **19 595
observationer**. De tre könsvalen har 6 517 kvinnor, 6 517 män och 6 561
källtotaler. Olika radantal betyder att könsuppdelning inte finns för alla
identiteter; inga saknade kvinnor-/mänrader har konstruerats.

**39 observerade lärosäteskoder inklusive Riket** och **52 program** förekommer
någon gång. Alla 81 metadataalternativ för lärosäten och alla 78 programval
begärdes varje termin; 42 lärosätesalternativ saknar observationer i hela
perioden. Metadataalternativ är således inte faktiska årliga observationer.
Hortonomexamen och Jägmästarexamen förekommer i historiken men inte i HT2026.
Källans egna totalvärden ingår, utan summering eller medelvärdesbildning.

100 CSV-exporter och 80 JSON-kontroller är sparade: 40 exakta
CSV-partitionsjämförelser, 60 nationella könsrotsvar och 20 separata
stabilitetskontroller. Totalt **4 384** källtotaler/annonserade värden har
jämförts. Samtliga kontroller passerar. Inga saknat-/sekretessmarkörer
förekommer i uttagen; detta fastställer inte källans allmänna sekretessregler.

| Period | Observationer | Observerade lärosäten inkl. Riket | Program |
|---|---:|---:|---:|
| HT2026 | 1 337 | 36 | 50 |
| VT2026 | 739 | 31 | 33 |
| HT2025 | 1 341 | 36 | 50 |
| VT2025 | 721 | 31 | 33 |
| HT2024 | 1 328 | 36 | 49 |
| VT2024 | 708 | 30 | 33 |
| HT2023 | 1 311 | 36 | 49 |
| VT2023 | 687 | 30 | 33 |
| HT2022 | 1 317 | 36 | 49 |
| VT2022 | 682 | 30 | 32 |
| HT2021 | 1 293 | 35 | 49 |
| VT2021 | 664 | 30 | 32 |
| HT2020 | 1 266 | 35 | 49 |
| VT2020 | 641 | 30 | 33 |
| HT2019 | 1 245 | 35 | 48 |
| VT2019 | 603 | 30 | 30 |
| HT2018 | 1 250 | 35 | 48 |
| VT2018 | 629 | 30 | 30 |
| HT2017 | 1 244 | 35 | 48 |
| VT2017 | 589 | 30 | 29 |

Samlad maskinläsbar rapport: `uka-99-full-collection-2026-11-10.json`.
Nollbudgetåterstarten kontrollerar samtliga sparade CSV-byten, kvitton,
JSON-svar, manifest och stagingrader; 20 terminer återspelas med **0 nya
exporter, 0 nya JSON-anrop och 0 insättningar**, med identiska
terminskontrollsummor. SQLite `quick_check` ger `ok`.

15 syntetiska indikator-99-tester och totalt 124 lokala UKÄ-tester passerar.
GitHub-run 42768653140 passerar 124 tester, endast Staging · 99 och
samlad täckningsrapport; HST-steg och bred JSON-diagnostik hoppas över.
Indikator-99-testworkflowet 42768652910 passerar också.

Återstartspaket: `UKA_99_Soktryck_VT2017_HT2026_2026-11-10.zip`.
Det innehåller `collection-99/99-full.sqlite`, metadata, alla CSV-källsvar,
JSON-kontroller, exportkvitton, kontrollpunkter, filhashar, äldre referenser,
kod, tester och rapporter. De äldre 1 337 stagingvärdena hålls separat och
ska inte adderas till de 19 595 nya observationerna. Bara indikator 99:s
data ingår. Arkiv- och leveranshash redovisas i `uka-99-delivery-2026-11-10.json`.

Efter uppackning från paketets rot:

```bash
python -m pip install -r requirements.txt
python scripts/uka_99_verify.py --root .
```

Själva verifieringen spärrar nätverksanrop och ska ge 20 terminer,
19 595 observationer, oförändrade staginghashar och återverifierade
66/66 respektive 1 337/1 337 referensvärden. `checksums.json` kontrollerar
paketfilerna före återspelningen.

## Begränsningar och exakt nästa åtgärd

Alla beställda hämtningar är genomförda. Inga ytterligare källuttag behövs
för denna beställning. Före en separat produktionsintegration: fastställ
kraven för oberoende kontroll av varje detaljcell, sekretess och källrevision.
Återanvänd paketet; ändra inte dess frysta manifest för en ny revision.

CSV-layoutar kan dela källfel. De nya JSON-rotsvaren verifierar nationella
programvärden och lärosätens totalvärden per kön, inte varje programvärde
inom varje lärosäte. Äldre slutna JSON-grafer verifierar dessutom pilotens
1 337 värden, men är inte samtidiga nya källsvar. Övriga terminers alla
detaljceller har inte jämförts mot separata JSON-blad. Officiellt
oföränderligt källversions-ID och sekretesssemantik är inte fastställda.
Därför förblir `full_source_coverage_verified`, `source_release_verified`
och `publish_allowed` false även efter full hämtning. Ingen merge,
migration eller produktionspublicering har gjorts.
