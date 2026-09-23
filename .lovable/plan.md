# Städa databasen före eventuell uppgradering

Mål: frigöra diskutrymme och minska belastningen utan att röra publicerad, synlig data — och lägga grunden för att gränssnittet senare läser filtrerade/aggregerade urval i stället för allt på en gång.

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

Kör den befintliga, säkra städfunktionen `etl_cleanup_failed_batch` för de fyra inaktiva batcharna, en i taget, med takgräns per anrop. Ingen ny SQL-behörighet, ingen DELETE utanför funktionen.

Efter varje batch: kontrollera att antalet rader för aktiva batchar är oförändrat (4 472 496 + 102 816 + 10) och att `indicator_active_batches` pekar på samma batchar som nu.

Den äldre lyckade testbatchen (`ff9beab1…`) städas bara efter uttrycklig bekräftelse att den inte behöver sparas som referens.

## Steg 2 — Återvinn utrymme

Efter rensningen körs ett underhållspass på `observations` och `etl_batch_chunks` så att det frigjorda utrymmet faktiskt återlämnas i stället för att bara markeras som ledigt. Detta görs som läsblockeringsfri åtgärd där det är möjligt; om en tyngre variant behövs körs den vid låg trafik och beskrivs innan den körs.

Förväntat resultat: ca 300 MB mindre i observationstabellen och ca 80 MB mindre i chunktabellen.

## Steg 3 — Läsmodell för E3 (förberedelse, byggs senare)

Eftersom gränssnittet framöver ska filtrera i stället för att visa allt, förbereds:

- En aggregerad läsvy per indikator, geografi, period och de dimensioner som faktiskt används i diagram, så att en vanlig sidvisning läser hundratals rader i stället för miljoner.
- Ett index som matchar de faktiska filtren (indikator + geografi + period).
- Serverfunktionen som läser statistik får obligatoriska filterparametrar, så att inget anrop kan begära hela datamängden.

Detta byggs när filtreringen och visualiseringarna specificeras — planen låser bara riktningen.

## Vad som inte görs

- Ingen uppgradering av databasinstansen nu. Disk och minne ligger inte på larmnivå, och steg 1–2 tar bort en betydande del av trycket.
- Ingen ändring av R-skript, arbetsflöde i GitHub eller ETL-endpoints.
- Ingen förändring av publicerad, synlig data.

## Tekniska detaljer

- Städning sker via `public.etl_cleanup_failed_batch(p_batch_id, p_max_rows)` (SECURITY DEFINER, EXECUTE endast för servern).
- Verifiering sker med läsande frågor mot `etl_batches`, `indicator_active_batches` och radantal per batch före och efter.
- Kontroll av tabellstorlek före/efter med `pg_total_relation_size`.
