# UKÄ 99 – Söktryck: produktionspublicering 2026-11-10

Publiceringsgrund och källrevision för indikator 99 (`uka-soktryck-yrkesprogram`).
Endast denna indikator berördes. Status för metod och insamling: [uka-indicator-99.md](uka-indicator-99.md).

## Publiceringsgrund

- Användaren godkände uttryckligen uppladdning av paketet och produktionspublicering av
  endast indikator 99, efter merge av PR #82 (`64b0901`).
- Underlag: endast `collection-99/99-full.sqlite` i
  `UKA_99_Soktryck_VT2017_HT2026_2026-11-10.zip`
  (SHA-256 `3cf8af5c59105cb1b74b5ad485072c6229e2c5e41df833c8f2507003696fe8ba`, 3 845 784 byte).
  Staging-SHA-256 `34a746d507c59e16d084c1b5582060cfa5108a316da10e72a67025b2a9fb9e3b`.
- Ingen ny källhämtning. `reference-99` lästes inte och adderades inte.

## Granskningsflaggor (oförändrade)

| Flagga | Värde |
|---|---|
| `full_source_coverage_verified` | false |
| `source_release_verified` | false |
| Paketets `publish_allowed` | false |
| Användargodkänd publicering | true |

Nya rot-JSON- och CSV-partitionskontroller passerar (100 CSV-exporter, 80 JSON-kontroller,
4 384 jämförda källtotaler). Varje historisk detaljcell, sekretessemantik och en officiell,
oföränderlig källrevision är **inte** oberoende verifierade. Därför sätts inget
`kalla_uppdaterad_datum`; Tillgänglighetsdatum blir hämtdatum 2026-11-10.
Flaggorna och grunden lagras i manifestet och i körningens `data_source_runs.details`.

## Kontroller före skrivning

- Paketets SHA-256 och storlek matchar godkänt paket.
- `checksums.json`: 531 filer verifierade.
- `scripts/uka_99_verify.py --root .` (nätverksspärrad): 20 terminer, 19 595 observationer,
  0 nya anrop/exporter/insättningar, oförändrade staginghashar, 66/66 och 1 337/1 337
  referensvärden exakta, `publish_allowed: false`.
- Normalisering (`scripts/uka_99_publish_verified.py`): lärosäteskod → namn via paketets
  metadata (`uni:1` → Riket), 39 lärosäten inkl. Riket, programdimension `program` enligt
  `normalize_uka` (källans program-Total utan nyckel), 52 program + Total, ingen
  åldersdimension, Kvinnor 6 517 / Män 6 517 / Total 6 561, 0 dubbletter, radantal per
  termin och kön lika med terminssammanfattningarna. Värden lagras exakt
  (t.ex. `2.3`, `0`, `1E+1` = 10); inga nollor för frånvaro och inga beräknade totaler.
- Jämförelse mot dåvarande aktiva batch `4892c284-c21a-4ec5-b9c8-2b78b5ce61db` (äldre
  R-export 2026-11-09): 19 595/19 595 identiteter och värden lika. Detta visar
  stabilitet mellan två uttag, inte oberoende källverifiering.

## Import och aktivering

- Importnyckel `uka-99-2026-11-10-3cf8af5c5910`, manifesthash
  `5c261a7e812934b86eaf1c3a13770c36a26c5333afd109fddaaf0a430c3eea91`.
- Ny batch `be0322b3-7016-4d03-9619-9bac577b381b`, körning `b87e2921-3d04-4f51-bb65-7bb0f97423a6`.
- 4 chunkar (5 000, 5 000, 5 000, 4 595), alla mot manifestets SHA-256.
- Servern kontrollerade täckning per termin/kön, chunkar, dubbletter, värden, Riket i
  varje termin och LTU innan atomisk aktivering 2026-11-10 07:53:22 UTC.
- Föregående batch `4892c284-…` behålls för rollback (19 595 rader, status succeeded).
- Aggregat omräknade: endast indikator 99 ändrad (`changed_indicators: 1`).

## Verifiering efter import

- Aktiv batch: 19 595 rader, 20 terminer, 39 lärosäten, 0 ålders-/nullvärden.
- Alla 19 595 lagrade värden lika med paketet (decimal jämförelse).
- Webbsidans serverfunktion `getUkaEducation` (LTU): 570 rader för 99, 20 terminer,
  190 per kön, 0 avvikelser; HT2026 Samtliga 1,2. Sidan visar "Senast hämtad: 2026-11-10".
- Riket via sidans publika läsväg (`agg_uka_university`, publik nyckel): 2 473 rader, 0 avvikelser;
  HT2026 Samtliga 2,1.
- Övriga UKÄ-indikatorers aktiva batchar oförändrade; HST-uppladdningen
  `5c6a7d55-…` (155/231 chunkar) rördes inte.

## Rollback

Sätt `uka_active_batches.active_batch_id` för `uka-soktryck-yrkesprogram` tillbaka till
`4892c284-c21a-4ec5-b9c8-2b78b5ce61db` och kör `agg_refresh_uka()`.

## Kända begränsningar

- Riket-vyn i `getUkaEducation` returnerar redan ett serialiseringsfel
  ("pending output limit") eftersom Riket har ~139 000 aggregatrader, främst HST.
  Felet beror inte på indikator 99 (oförändrat radantal) men hindrar visning av Riket på sidan.
- Den äldre R-ETL:n (`etl-uka.yml`, `uka_finalize_batch`) raderar föregående batch och kan
  ersätta denna publicering vid en körning för "all" eller 99.
