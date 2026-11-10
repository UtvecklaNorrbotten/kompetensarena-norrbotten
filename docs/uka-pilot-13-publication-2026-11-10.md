# UKÄ 13 – Förstahandssökande till yrkesexamensprogram: pilotpublicering 2026-11-10

Pilot för den gemensamma manifestlåsta importvägen (`uka_snapshot_*`) för de åtta
CSV-stagade indikatorerna (13, 31, 97, 108, 136, 77, 134, 135). Endast 13 är
publicerad. De sju övriga publiceras först efter användarens granskning av detta bevis.

## Publiceringsgrund

- Uttryckligt användargodkännande (Joe Lindehag, 2026-11-10) att publicera pilot 13
  genom återanvändning av den redan aktiva batchen inom databasen, efter exakt jämförelse
  mot ett oberoende, lokalt beräknat fryst manifest. Ingen ZIP-fil hämtades, ingen extern
  uppladdning och ingen ny UKÄ-hämtning gjordes. Bara icke-reversibla hashvärden och
  täckningsantal lämnade användarens miljö.
- Användarens kompletterande kontroll (read-only, 15:28 UTC) säger att alla 105 perioder i
  de åtta indikatorerna (468 872 rader) matchar stagingpaketet exakt.
- `source_release_verified = false` och `full_source_coverage_verified = false` är bundna i
  manifestet och i körningens metadata. Publiceringen påstår ingen källrevision.

## Fryst manifest

`docs/data/uka-snapshot-2026-11-10-all-pilot-13.json`: policy
`csv-all-universities-partitions-every-root-v1`, snapshot `2026-11-10-all`, arkiv
`1be12b057d06285fa97b9eaa314d31e0898de57130f7c4d99c3a4093e2eb4170`, 73 268 rader,
20 terminer (VT2017–HT2026), 240 täckningsceller (period × kön × ålder).
Filen återskapades ur det serverbundna manifestet efter en repo-synk, och alla
20 periodrader (termin, radantal, SHA-256) jämfördes rad för rad mot användarens
meddelande: identiska.

Fingeravtryck: `jsonb_build_array(period, university, gender, dimensions, värdetext)::text`.
Värdetext är fast decimaltext utan avslutande decimalnollor. Raderna sorteras `COLLATE "C"`,
sammanfogas med `\n` utan avslutande radbrytning och hashas med SHA-256 (`extensions.digest`).
Inga totaler summeras. Kön bevaras, och `aldersgrupp` utelämnas för teknisk Total.

## Före aktivering

1. Rollback-tester (`tests/uka-snapshot-import.sql`, block A, B1, B2, C, D) kördes mot
   produktionsdatabasen före aktiveringen. Varje block avslutas med ett undantag, så inget
   sparades. Samtliga rader blev PASS/t:
   - A: ofullständigt manifest (saknad täckning, saknad period, flagga true, fel täckningssumma)
     vägras; ändrad periodhash vägras (22000); ändrat värde i källbatchen vägras;
     fel API/indikator-par, fel nyckelprefix och främmande källbatch (HST) vägras;
     inget skrevs.
   - B1: 15 planerade chunkar; glesa chunkar [0, 2, 14] tas emot; dubblett ger `duplicate`;
     index utanför planen vägras; ofullständig finalisering vägras (3/15);
     återstart återanvänder samma batch; annat manifest för samma nyckel, parallell import
     och samma manifest under annan nyckel vägras; äldre `uka_finalize_batch`/`uka_abort_batch`/
     `uka_store_chunk`, HST- och 99-vägarna samt uppladdning in i en kopieringsimport vägras.
   - B2 (136): full kopiering och finalisering, staging- och källkontroll ok,
     tidigare batch kvar, aggregat = observationer, hashar lika; ny finalisering ger
     `already_published`; manifest, publicerad import och kopieringsplan går inte att ändra
     eller radera.
   - C (136): ändrad källrad före kopiering vägras; ändrad källrad efter kopiering, ändrad
     stagingrad och byte av aktiv batch stoppar finaliseringen; aktiv batch oförändrad.
   - D: icke-kanonisk värdetext (`5.0`), teknisk ålder `Total` som nyckel och ändrad payload
     vägras; fullständig uppladdning i omvänd ordning med dubblett publiceras korrekt.
   - Block för full finalisering körs på 136 (9 899 rader). En finalisering av 13 med
     aggregatomräkning tar cirka 3 minuter, längre än SQL-verktygets begränsning.
2. Uppladdarens enhetstester (`tests/test_uka_snapshot_publish_verified.py`): 11 av 11 ok.
   Kanonisk rad och periodhash är kontrollerade mot PostgreSQL-referensvärden.
3. Read-only kontroll: `uka_snapshot_verify_batch` mot källbatchen
   `34e7afd0-6339-430b-8a30-1ac6cd2ac230` gav 20/20 perioder och 73 268 rader. Täckningsavvikelser,
   dubblettidentiteter, ogiltiga kön/åldrar, inexakt värdetext och aggregatkollisioner: alla 0.

## Publicering

- Import `uka-13-snapshot-2026-11-10-all-1be12b057d06`, läge copy, manifesthash
  `5d2a568090dccdbb31115b30694174ab90205b5073e7044a73a28a96bc623994`.
- Servern verifierade källbatchen igen vid start och gjorde en plan med 15 chunkar om högst
  5000 rader. Varje kopierad chunk kontrollerades mot planens hash, och servern tog emot
  15 av 15. Vid finaliseringen kontrollerades både staging och källa, och aktiveringen
  skedde atomiskt med aggregatomräkningen.
- Aktiverad 2026-11-10 13:35:08 UTC. Ny aktiv batch `8a557419-b53f-4689-945b-b8e6a75f72bc`.
- Tidigare batch `34e7afd0-6339-430b-8a30-1ac6cd2ac230` finns kvar (status succeeded, 73 268 rader).
- `data_source_runs`: succeeded, 73 268 rader, `periods_verified` 20, flaggorna false.
  `indicator_metadata`: källans uppdateringsdatum saknas (NULL), hämtad och
  tillgänglighetsdatum 2026-11-10.

## Efter aktivering

- En ny körning av uppladdaren med `--copy` gav `resumed` och ingen skrivning.
  Återläsningen gav 20 perioder, 73 268 rader och 0 avvikelser.
- Oberoende SQL-omräkning av fingeravtrycken för **både** ny och tidigare batch gav
  identiska värden med användarens 20 periodhashar (`diff` utan skillnad).
- Täckning i ny batch: 240 celler och 73 268 rader.
- `agg_uka_university` för 13: 73 268 rader, summa 21 065 288, samma som före publiceringen.
  Observationer som saknas i aggregatet: 0. Aggregatrader som saknas bland observationerna: 0.
- Utbildningssidan (`/omraden/utbildning/yrkesexamensprogram`, begränsad läsväg):
  LTU visar 2 070 och Riket 104 093 (Samtliga, HT 2026), med "Senast hämtad: 2026-11-10".
  Inga sidfel och inga misslyckade anrop.
- Övriga aktiva batchar är oförändrade. HST `5c6a7d55`, 99 `be0322b3`, de sju väntande
  (31, 97, 108, 136, 77, 134, 135) och de regionala indikatorerna har samma batch-id,
  aktiveringstid, aggregatradantal och aggregatsumma som före publiceringen.

## Varför aggregeringen är säker

`agg_refresh_uka` grupperar på (lärosäte, period, kön, dimensionsnycklar, dimensionsvärden)
och använder `sum()`. Kontrollen `aggregate_collision = 0` visar att ingen sådan grupp har mer
än en observation. Varje aggregatrad är alltså exakt en observation, och inget summeras.
Det bekräftas av att EXCEPT-jämförelsen ger 0 i båda riktningarna. Omräkningen är inkrementell:
bara indikatorer vars aktiva batch ändrats räknas om (`changed_indicators: 1`).

## Rollback

Den tidigare batchen finns kvar, liksom `previous_batch_id` i `uka_verified_imports`.
En återställning är ett nytt, uttryckligen godkänt steg som pekar tillbaka `uka_active_batches`
för 13 till `34e7afd0` och räknar om aggregaten. Ingen data raderas. Det steget är inte byggt
som funktion och kräver en migration.

## Källbegränsningar

- Ingen källrevision är verifierad, och full källtäckning är inte verifierad
  (flaggorna står på false).
- Fingeravtrycket bygger på värdet som double precision → numeric. Värden med fler än cirka
  15 signifikanta siffror skulle avrundas. För 13 är alla värden heltal (1–104 093).

## Repo-notering

Under arbetet synkades repot från GitHub. Då försvann den ursprungliga migrationsfilen och
journalposten. Det som faktiskt är installerat i databasen finns nu som
`drizzle/uka_snapshot_verified_import.applied.sql`. Filen är byggd ur katalogen, ligger
utanför `migrations/` och ska inte köras igen. Uppladdaren, testerna och manifestet är återställda.
