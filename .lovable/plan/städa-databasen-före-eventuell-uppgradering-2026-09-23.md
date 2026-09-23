# Städa databasen före eventuell uppgradering

Mål: frigöra diskutrymme och minska belastningen utan att röra publicerad, synlig data — och lägga grunden för att gränssnittet senare läser filtrerade urval i stället för allt på en gång.

## Svar: skulle mer RAM korta ner de 2 timmarna?

Nej, inte nämnvärt. Tiden går åt på två ställen som inte begränsas av databasens minne:

- **Hämtningen från SCB** (flera hundra anrop mot deras API, ett i taget) — styrs av SCB:s svarstider, inte av vår databas.
- **Överföringen chunk för chunk** — knappt 900 separata anrop där varje chunk byggs i R och skickas över nätet. Själva databasinsättningen tar ca 0,3 sekunder per chunk; resten är väntan.

Mer minne hjälper alltså inte. Det som faktiskt kortar ner körtiden är större chunkar och parallella anrop — en separat förbättring i ETL-flödet (R + arbetsflödet i GitHub) som vi kan ta som eget steg när du vill. Databasinstansen behöver inte uppgraderas nu.

## Nuläge (avläst nu)

- `observations`: 2 586 MB totalt.
- Aktiv, synlig data: 4 472 496 rader (E3) + 102 816 rader (E3-testindikator) + 10 exempelrader.
- Inaktiv data som ingen användare kan se:
  - 305 000 rader (misslyckad import)
  - 145 000 rader (misslyckad import, timeout-händelsen)
  - 84 rader (misslyckad import)
  - 102 816 rader (äldre lyckad testbatch som ersatts av en nyare)
  - Totalt ca 552 900 rader.
- `etl_batch_chunks`: 80 MB i 986 kvarvarande rader från avbrutna importer.

## Steg 1 — Rensa inaktiva importrader

Kör den befintliga, säkra städfunktionen `etl_cleanup_failed_batch` för de inaktiva batcharna, en i taget, med takgräns per anrop. Ingen ny behörighet, ingen fri radering.

Efter varje batch: kontrollera att antalet rader för aktiva batchar är oförändrat och att den aktiva E3-batchen fortfarande pekas ut som aktiv.

## Steg 2 — Ta bort E3-testindikatorn helt

Testindikatorn `e3-matchning-utbildning-etl-test` (endast synlig för administratörer) har fyllt sitt syfte. Den tas bort i tre led:

1. Dess aktiva batch kopplas bort och dess 102 816 rader städas via samma säkra funktion.
2. Dess batchar, chunkar, körningsloggar och metadata tas bort.
3. Själva indikatorposten tas bort.

Detta frigör ytterligare ca 100 000 rader och minskar risken att testdata förväxlas med skarp data. Eftersom detta raderar data kräver det ett uttryckligt ja i godkännandesteget när det körs.

Kvar efteråt: skarp E3-data och exempelindikatorn — inget annat påverkas.

## Steg 3 — Återvinn utrymme

Efter rensningen körs ett underhållspass på `observations` och `etl_batch_chunks` så att det frigjorda utrymmet faktiskt återlämnas i stället för att bara markeras som ledigt.

Förväntat resultat: ca 400 MB mindre i observationstabellen och ca 80 MB mindre i chunktabellen.

## Steg 4 — Läsmodell för E3 (förberedelse, byggs senare)

Eftersom gränssnittet framöver ska filtrera i stället för att visa allt, förbereds:

- En aggregerad läsvy per indikator, geografi, period och de dimensioner som faktiskt används i diagram.
- Ett index som matchar de faktiska filtren (indikator + geografi + period).
- Serverfunktionen som läser statistik får obligatoriska filterparametrar, så att inget anrop kan begära hela datamängden.

Byggs när filtreringen och visualiseringarna specificeras — planen låser bara riktningen.

## Vad som inte görs

- Ingen uppgradering av databasinstansen.
- Ingen ändring av R-skript, arbetsflöde i GitHub eller ETL-endpoints i detta steg (snabbare import hanteras separat).
- Ingen förändring av skarp, publicerad E3-data.

## Tekniska detaljer

- Städning sker via `public.etl_cleanup_failed_batch(p_batch_id, p_max_rows)` (SECURITY DEFINER, EXECUTE endast för servern).
- Borttagning av testindikatorn görs som migration i rätt ordning: `indicator_active_batches` → `observations` → `etl_batch_chunks` → `etl_batches` → `data_source_runs` → `indicator_metadata` → `indicators`.
- Verifiering med läsande frågor mot `etl_batches`, `indicator_active_batches` och radantal per batch före och efter, samt tabellstorlek via `pg_total_relation_size`.
