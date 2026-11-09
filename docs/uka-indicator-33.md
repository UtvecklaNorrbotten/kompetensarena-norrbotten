# UKÄ 33 – Helårsstudenter

Senaste kontrollpunkt: **4**, alla tre beställda steg genomförda. Hela
2016/17–2025/26 är hämtad och kontrollerad i separat återstartbar staging:
**1 151 372 observationer**. Ingen publicering eller merge. Begränsningar och
exakt nästa åtgärd står sist.

## Kontrollpunkt 1 – återställning 2026-11-09

Arbetsgren `fix/uka-verified-checkpoint-import`, PR #82 (öppen draft).
Utgångscommit `91b27e2fa8fd3ca54db20fc3a36b57417fa8ef0f`.
Endast indikator 33. Inga nya UKÄ-anrop, ingen produktionsimport eller merge.

Återställt och återspelat gemensam bas från run `42227843941`, artefakt
`13506706544`, samt endast staging-33 från run `42242045989`, artefakt
`13517595926`. ZIP SHA-256:

- Bas: `9df36889d1019ec8b1610244ae602e3bd4c5e4991c7082171fed283ec2d9f513`.
- Staging: `d9967c119beefe3cf1cda798f01d6f0be83a4c80f79e00bd4ffad6801ea8d0d4` (matchar GitHubs artefaktdigest).
- CSV-fixtur: `d7cc49409203a2dab448c63b15bc478c82bf0d9485f2bc233a669a5e3f0e7e5a`.

Manifest, tidigare färdiga stagingrader och källkvitton har kontrollerats offline.
Nationell staging är oförändrad: 1/120 urval, 9 731 observationer,
SHA-256 `8dc51aa302a694b4af67eddebb358ec0bd0fe0c7442d5a4df669f70fc06c27cc`.
Samtliga nio CSV-referensjämförelser och sju exportkvitton återspelas med noll
exporter. Delpaketet har fortsatt 1 235 identiska överlapp och saknar 8 496
nationella observationer. Det får inte färdigmarkera det nationella jobbet.
84 befintliga UKÄ-tester passerar lokalt efter installation av requests/beautifulsoup4.

Belägg: [återstart](UKA_SINGLE_INDICATOR.md), [kampanj](UKA_CAMPAIGN.md),
[CSV-jämförelser](uka-csv-bulk-evidence-2026-11-06.json),
[nationell spärr](uka-csv-staging-audit-2026-11-06.json),
[ämnesvägar](uka-hst-subject-paths-2026-11-06.json).

## Dimensioner och kvarstående osäkerheter

| Dimension | Fryst underlag | Återstår |
|---|---|---|
| Period | 2016/17–2025/26 i planen | Full täckning för mellanliggande år |
| Lärosäte | 78 filteralternativ inklusive Riket | Period- och dimensionsspecifika observationer; alternativ är inte täckningsbevis |
| Kön | Kvinnor, Män, källans Total | Övriga lärosäten/perioder för alla kombinationer |
| Ålder | -24, 25-34, 35-, källans Total | Samma; teknisk total får inte konstrueras |
| Studieform | Fristående kurser, Generella program, Konstnärliga program, Yrkesexamensprogram samt källans Total | Förekomst per lärosäte och ämnesväg |
| Ämne | 9 områden, 41 delområden, 179 grupper samt Total | Hela föräldravägen krävs, särskilt återanvända Övrigt |

CSV-bredderna för Riket/LTU/171 är verifierade mot separata CSV-uttag 2025/26
och 2016/17. Det visar att uppdelningen i dessa paket fungerar; det bevisar
inte fullständighet för alla andra lärosäten eller år. Nationell JSON-referens
finns för Kvinnor/-24/2025-26, medan lärosäte 171 har tolv avslutade
JSON-referensgrafer 2025/26 (3 kön × 4 åldrar).

Sekretess/null, legitima tomma urval och revisioner är ännu inte generellt
verifierade. Frånvaro av 171 i breda positiva svar för 2016/17 är avgränsad
evidens, inte ett generellt tillstånd att behandla 500/nollbyte som tom data.
Snapshotdatum är inte en verifierad källversion.

## Nästa åtgärd vid kontrollpunkt 1 (nu genomförd)

Lås ett pilotmanifest för 171/2025-26 över samtliga kön och åldrar. Återbygg
de tolv JSON-graferna från hashkontrollerade cachekällor med nätbudget noll,
jämför CSV:s samtliga nycklar/värden och skriv 144 observationer atomiskt till
egna pakettabeller i befintlig stagingdatabas. Behåll nationell plan/manifest
och dess jobbstatus orörda. Verifiera återstart, dubblett-, manipulations- och
avbrottsskydd innan fler paket prövas.

## Kontrollpunkt 2 – CSV-pilot 2026-11-09

Pilot: **Akademi för Ledarskap och Teologi (uni:171), 2025/26**.
Samtliga tolv kombinationer av kön och ålder är verifierade mot nycklar och
värden i tolv separat återbyggda JSON-grafer. Varje kombination har 12
observationer; paketet har totalt **144**. Inga totaler har summerats.

Belägg och exakta kontrollsummor finns i
[pilotrapporten](uka-hst-csv-pilot-2026-11-09.json) och
[det låsta pilotmanifestet](../config/uka_hst_csv_pilot.json).

Importören `scripts/uka_hst_csv_staging.py` kontrollerar CSV-kvitto, metadata-
projektion, källhierarki, plan-ID, snapshot, köernas bytekontrollsummor och
exakt täckning per lärosäte/kön/ålder. Referensgrafer återbyggs från roten i
tillfälliga köer med nätbudget noll; varje källsvars hash och grafens avslut
kontrolleras igen. Sparad `done`-status räcker inte.

Paketets manifest, observationer och färdigmarkering skrivs i en SQLite-
transaktion till `csv_packages`/`csv_observations` i befintlig `campaign.sqlite`.
Paketets egna gränser hålls skilda från de nationella jobben. Nationellt
manifest, policy, snapshot och jobbstatus ändras inte. Vid samma manifest
är återspelning en kontroll utan nya insättningar. Ett ändrat manifest för
samma scope stoppas; överlappande CSV-paket kan inte skriva dubbla nycklar.
Ändrade sparade CSV-rader stoppar även vanlig Campaign-återstart.

**Resultat:** första skrivningen och separat återstart passerar med noll nya
anrop/exporter. Vanlig kampanjåterstart passerar också. Nationell staging är
fortfarande 1/120 och 9 731 observationer med samma kontrollsumma som ovan.
12 av paketets observationer finns redan i den nationella referensen; 144
får därför inte adderas till 9 731 som ett antal unika observationer.

96 lokala UKÄ-tester passerar, varav 12 nya tester för paketstaging:
täcknings- och värdespärrar, manifestbindning, återstart, samtidiga skrivare,
källhashar, ändrade köer/rader, nationell värdekonflikt, null/zero-skillnad,
dubbletter och transaktionsavbrott. Null-testet är syntetiskt och fastställer
inte källans sekretesssemantik. YAML och `git diff --check` passerar.

Workflowet `uka-staging.yml` kör nu endast **33** vid PR-kontroll. Manuell
körning väljer exakt en indikator (33 som förval). HST-steget återspelar
piloten två gånger och sparar paketdatabas/manifest/rapporter i staging-33-
artefakten. Ingen ny utredning eller staging av övriga indikatorer har gjorts.

GitHub-verifiering av funktionscommit `4396514dca173c95ae968f3b2173858419adcc50`:
run [42630773876](https://github.com/UtvecklaNorrbotten/kompetensarena-norrbotten/actions/runs/42630773876),
96 tester och endast `Staging · 33`. CSV-skrivning, återstart och uppladdning
av stagingartefakten passerar. Använd denna körnings `uka-staging-33` som
ny återstartspunkt; pilotmanifestet och den gemensamma basen behålls.

Avvikelse vid PR-uppdateringen: GitHub utvärderade PR:ens samlade ändrade
sökvägar och startade även äldre JSON-diagnostik, run `42630774000`.
Den återspelade tidigare kontroller för övriga nio indikatorer; deras
nationella köloggar visar `processed_this_run: 0` och
`network_requests_this_run: 0`. Ingen ny indikator påbörjades, men den
automatiska återspelningen låg utanför den avsedda avgränsningen.
`uka-json-probe.yml` har därför fått en jobbspärr: endast uttrycklig manuell
körning. PR-regressionstester finns kvar i HST-stagingworkflowet.

### Återspela kontrollpunkten

Återställ basen och staging-33 enligt kontrollpunkt 1 till `base/uka-json-probe`
respektive `output/uka-staging`. Packa upp den befintliga CSV-fixturen till
`output/csv-reference`. Behåll alla befintliga filer och manifest.

```bash
python scripts/uka_hst_csv_staging.py \
  --root output/uka-staging \
  --csv-root output/csv-reference \
  --metadata output/csv-reference/export-filters.json \
  --reference-root base/uka-json-probe/validation \
  --base base/uka-json-probe \
  --output output/uka-staging/csv-pilot-resume.json
```

Kommandot saknar live-läge. Efter den första skrivningen ska `staging_written`
vara false, observationerna 144 och paketkontrollsumman
`ad5f56c8d946f2f7d31e027e889ff60ad99fc25258db87605d34a0a01e9e52c1`. Full källtäckning och verifierad källversion förblir
false, och publicering är alltid false. Originalbasen har giltighetstid till
2026-12-06 enligt återstartskontrollen; artefaktkedjan måste bevaras.

## Nästa åtgärd efter kontrollpunkt 2 (nu genomförd)

Fortsätt endast HST. Nästa avgränsade paket bör vara **LTU (32), Kvinnor,
-24, 2025/26**, där det redan finns 366 matchande CSV-/JSON-observationer.
Börja offline: inför ett manifest som skiljer CSV-exportens breda urval från
det uttryckliga stagingurvalet. Lås projektionen till exakt 32/Kvinnor/-24
och verifiera den mot motsvarande del av den fullständigt återbyggda
nationella grafen. Det nuvarande pilotmanifestet eller nationella jobbet
får inte omtolkas. Testa att bred export, fel lärosäte, saknade ämnesvägar
och ändrade värden inte kan färdigmarkera ett större urval. Skriv först
efter exakt matchning, atomiskt och återstartbart med samma spärrar.

Ingen större tioårshämtning behövs för detta steg. Nya källanrop har budget
**0** tills nästa konkreta osäkerhet kräver ett separat avgränsat prov.
Återstående större luckor är övriga perioder/lärosäten/kombinationer,
tom-/sekretesssemantik och revisioner. Ingen produktionsanslutning eller merge.

## Kontrollpunkt 3 – LTU och ett helt år, 2026-11-09

Användaren har nu godkänt samtliga tre steg: LTU-projektion, ett kontrollerat
helårsuttag för alla lärosäten och därefter resterande nio HST-år om första
året passerar. Avgränsningen är fortsatt endast 33; ingen publicering/merge.

**Steg 1 klart:** LTU/Kvinnor/-24/2025-26 matchar exakt **366/366**
observationer efter att hela den frysta nationella JSON-grafen återbyggts
offline. Det breda CSV-uttaget och stagingurvalet binds nu separat i
[LTU-manifestet](../config/uka_hst_csv_ltu.json). Skrivning och återstart är
verifierade med noll nya anrop. Nationella rader, jobb och manifest är
oförändrade. Se [LTU-belägget](uka-hst-ltu-evidence-2026-11-09.json).

**Steg 2 klart:** en ny kampanj med snapshotnamn **2026-11-09** har skapats,
separat från 2026-11-06. Aktuella HST-filter har hämtats igen; de erbjuder
78 lärosätesalternativ, tre kön, fyra åldrar och perioderna 2016/17–2025/26.
Ämnesvägarna är oförändrade mot den frysta referensen. Snapshotnamnet är
fortfarande inte ett officiellt versions-ID från UKÄ.

2025/26 har **115 689** observationer och 50 observerade lärosäteskoder,
inklusive Riket. Alla 78 alternativ har uttryckligen efterfrågats. Årets
breda CSV är exakt lika unionen av två disjunkta lärosätesuttag och exakt
lika unionen av två disjunkta studieformsuttag. Inga nycklar, värden eller
totaler har konstruerats genom summering.

För samtliga tolv köns-/ålderskombinationer har även UKÄ:s positiva nationella
JSON-rotsvar kontrollerats: egna totaler, annonserade lärosäten, studieformer
och ämnesområden. Alla kontroller måste finnas med oförändrade värden i CSV.
Lärosätesmängden i CSV måste vara exakt samma som i respektive positiva
rotreferens. Oannonserade lärosäten redovisas per kombination utan att tomma
urval eller nollvärden skapas. Ett separat rotsvar efter hämtningen matchar
svaret före kontrollerna. Se [årskontrollen](uka-hst-year-check-2026-11-09.json).

**Steg 3 pågår:** `scripts/uka_hst_full_csv.py` hämtar resterande nio år med
samma spärrar. Budget för detta block: högst 45 nya CSV-exporter och 117
JSON-anrop. Varje år skrivs atomiskt tillsammans med sin kontrollsumma;
fel lämnar en blockerad kontrollpunkt och ingen färdigmarkering för året.
Återstart validerar tidigare stagingrader och hoppar över färdiga år.

Viktig begränsning: lika breda och uppdelade CSV-exporter kan dela samma
källfel. JSON-rotkontrollerna motverkar felaktigt urval och saknade lärosäten,
men verifierar inte varje detaljcell mot en oberoende JSON-bladreferens.
Källans sekretessmarkörer bevaras; deras semantik är inte allmänt fastställd.
Därför förblir `full_source_coverage_verified`, `source_release_verified`
och `publish_allowed` false även om alla tio år har hämtats och kontrollerats.

108 lokala UKÄ-tester passerar. PR-workflowet återspelar både den ursprungliga
piloten och LTU-projektionen offline. Den nya helårskampanjen är separat och
startas inte automatiskt vid PR-uppdateringar.

## Nästa åtgärd vid kontrollpunkt 3 (nu genomförd)

Slutför den pågående, budgetbegränsade nioårskörningen. Vid fel: läs endast
det blockerade årets kontrollpunkt; ändra inga tidigare manifest och
färdigmarkera inte året. Efter sista året: kör återstart med noll nätbudget,
kontrollera alla års kontrollsummor och spara ett komplett återstartspaket
med källsvar, exportkvitton, metadata, SQLite och rapporter. Dokumentera
resultatet här. Ingen annan indikator, merge eller produktion ingår.

## Kontrollpunkt 4 – samtliga tre steg klara, 2026-11-09

**Steg 1:** LTU 366/366 verifierat och återstartbart, enligt kontrollpunkt 3.

**Steg 2:** 2025/26 passerar alla deklarerade helårskontroller: 115 689
observationer, två exakta CSV-partitionsjämförelser och tolv positiva
köns-/åldersreferenser. Årskontrollen gav klartecken till det tredje steget.

**Steg 3:** samtliga resterande nio år har hämtats och passerat samma kontroller.
Det finns nu **1 151 372 observationer**, tio färdiga år, tjugo exakta
CSV-layoutjämförelser, 120 kontrollerade nationella köns-/åldersrotsvar och
7 343 jämförda källtotaler/annonserade kontrollvärden. Samtliga tio separata
slutkontroller av nationell rot stämmer med respektive års första svar.
50 CSV-exporter och 130 JSON-svar är sparade tillsammans med sina kvitton.

| Period | Observationer | Observerade lärosäteskoder, inklusive Riket |
|---|---:|---:|
| 2025/26 | 115 689 | 50 |
| 2024/25 | 115 862 | 50 |
| 2023/24 | 115 600 | 50 |
| 2022/23 | 115 125 | 50 |
| 2021/22 | 114 926 | 49 |
| 2020/21 | 114 247 | 49 |
| 2019/20 | 114 511 | 49 |
| 2018/19 | 114 930 | 49 |
| 2017/18 | 114 990 | 49 |
| 2016/17 | 115 492 | 49 |

Alla **78** metadataalternativ för lärosäte efterfrågades uttryckligen varje
år. **56** koder, inklusive Riket, förekommer någon gång under perioden;
22 förekommer inte i något år. Års- och köns-/åldersspecifik frånvaro finns
i kontrollpunkternas positiva rotreferenser. Det är inte 78 uppmätta
lärosäten varje år, och frånvarande rader har inte ersatts med nollor.
Samtliga tre kön, fyra åldrar, fem studieformsval inklusive källans Total
och alla metadataannonserade ämnesvägar har ingått i varje exporturval.
Inga saknat-/sekretessmarkörer förekom i dessa exporter.

En kompletterande revisionskontroll visar att **9 731/9 731** observationer
för Kvinnor/-24/2025-26 är exakt oförändrade mot den fullständiga nationella
referensen från 2026-11-06. Detta gäller det urvalet, inte en identifierad
officiell källversion. Se [revisionskontrollen](uka-hst-revision-check-2026-11-09.json).

**Återstarten passerar:** samtliga tio år återspelas med **0** nya exporter,
**0** nya JSON-anrop och **0** nya insättningar. Alla års kontrollsummor
är identiska. Vid återstart verifieras även de sparade CSV-bytena och
kvittona, JSON-rotsvarens hash/kontext och de separata slutkontrollerna.
Ändrade råfiler, kontrollrader, manifest eller stagingrader stoppar återstart.

**Kod och tester:** 109 lokala UKÄ-tester passerar, inklusive avbrott,
dubbletter, felaktiga urval, ändrade källsvar,
ändrade råfiler, ändrat manifest och samtidiga skrivare. YAML och
`git diff --check` passerar. GitHub-run
[42637759039](https://github.com/UtvecklaNorrbotten/kompetensarena-norrbotten/actions/runs/42637759039)
verifierade föregående funktionskontrollpunkt med 108 tester, HST-pilot och
LTU-återstart; slutversionens verifiering redovisas separat efter commit.

Samlad maskinläsbar status finns i
[helårsrapporten](uka-hst-full-collection-2026-11-09.json).
Återstartspaketet heter `UKA_HST_2016-17_2025-26_2026-11-09.zip` och innehåller
SQLite, oförändrade CSV-källfiler, metadata, exportkvitton, JSON-kontroller,
kontrollpunkter, källfilernas kontrollsummor samt kod och äldre HST-referenser.
Den nya datamängden ligger i `hst-collection/hst-full.sqlite`; äldre pilot-
och LTU-staging hålls separat och ska inte adderas till de nya årssiffrorna.

Efter uppackning körs hela kontrollen utan nya källanrop från arkivets rot:

```bash
python scripts/uka_hst_full_csv.py \
  --root hst-collection \
  --metadata hst-collection/metadata.json \
  --snapshot 2026-11-09 --all-years
```

Budgetarna är noll som standard. Kommandot måste ge tio år, 1 151 372 rader,
oförändrade årskontrollsummor och noll nya anrop/exporter.

**Kvarstående begränsningar:** CSV-layoutjämförelser och JSON-rotsvar
verifierar de deklarerade kontrollerna; varje detaljcell har inte jämförts
mot ett separat JSON-blad. Två CSV-layoutar kan dela samma källfel.
Källans sekretesssemantik och ett officiellt oföränderligt källversions-ID
är inte fastställda. Därför förblir `full_source_coverage_verified`,
`source_release_verified` och `publish_allowed` false. Alla beställda
hämtningar är genomförda; dessa kvarstående produktionsspärrar får inte
döljas bakom tio färdiga år eller gröna tester.

## Exakt nästa åtgärd

Ingen ytterligare fullhämtning behövs för den beställda tioårsperioden.
Före en separat produktionsintegration: fastställ vilken verifiering som
ska krävas för detaljceller och sekretess, samt hur en ny källrevision ska
identifieras och publiceras atomiskt. Återanvänd detta paket som underlag;
ändra inte det frysta manifestet för att lägga till en ny period/revision.
Backendens återstartbara uppladdning och serverkontrollerade manifest är
fortsatt separat arbete. Ingen merge, migration eller publicering har gjorts,
och nästa indikator har inte startats.
