# UKÄ 33 – Helårsstudenter

Senaste kontrollpunkt: **2**, verifierat CSV-paket i återstartbar staging.
Nästa åtgärd står sist. Full tioårstäckning är inte klar.

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

## Exakt nästa åtgärd

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
