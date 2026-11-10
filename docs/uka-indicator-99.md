# UKÄ 99 – Söktryck till yrkesexamensprogram

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

## Genomfört

HT2026: 1 337 observationer; båda CSV-partitionskontrollerna och samtliga
könsrotsvar/stabilitetskontrollen passerar. 12 syntetiska tester passerar.
Historiken hämtas nu sekventiellt med kontrollpunkt per termin.

## Begränsningar och exakt nästa åtgärd

Fortsätt VT2026 och sedan återstående terminer i metadataordning. Stoppa vid
första blockerande avvikelse och utred innan nästa termin. Avsluta med samlad
nollbudgetåterstart, SHA-256-inventering och beständigt återstartspaket.

CSV-layoutar kan dela källfel. Varje detaljcell jämförs inte mot ett separat
JSON-blad. Officiellt oföränderligt källversions-ID och sekretesssemantik är
inte fastställda. Därför förblir `full_source_coverage_verified`,
`source_release_verified` och `publish_allowed` false även efter full hämtning.
