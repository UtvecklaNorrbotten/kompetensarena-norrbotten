# UKÄ 33 – Helårsstudenter

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

## Exakt nästa åtgärd vid denna kontrollpunkt

Lås ett pilotmanifest för 171/2025-26 över samtliga kön och åldrar. Återbygg
de tolv JSON-graferna från hashkontrollerade cachekällor med nätbudget noll,
jämför CSV:s samtliga nycklar/värden och skriv 144 observationer atomiskt till
egna pakettabeller i befintlig stagingdatabas. Behåll nationell plan/manifest
och dess jobbstatus orörda. Verifiera återstart, dubblett-, manipulations- och
avbrottsskydd innan fler paket prövas.
