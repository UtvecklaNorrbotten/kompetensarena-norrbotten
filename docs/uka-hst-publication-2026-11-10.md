# UKÄ 33 (HST) – publicering 2026-11-10

Användaren godkände att uppladdningen återupptas och att endast indikator 33 aktiveras, med den tidigare versionen kvar för rollback.

## Underlag
- `UKA_HST_2016-17_2025-26_2026-11-09.zip`: sha256 `2e65e8cd1e34ebbf67341a3fc472280af47b932dba693b16225ca08a9f1ccd1c`, 165 606 969 byte (kontrollerat i sandlådan).
- Endast `hst-collection/hst-full.sqlite` lästes. Samtliga 1 446 filer i `README_filer.json` stämmer i storlek och sha256. Inga legacy-reference-/staging-/pilotrader och ingen UKÄ-hämtning.

## Varför uppladdningen stannade
Den första uppladdningen (start 06:52 UTC) avbröts när sandlådan startades om. Uppladdaren och den uppackade filen fanns bara i `/tmp`, och skriptet fanns inte i repot. Servern hade då 155 chunkar, 0–153 och 155. Index 154 saknades alltså trots att 155 var mottagen.

## Återuppbyggd uppladdare
`scripts/uka_hst_publish_verified.py` gör följande:
- Normaliserar raderna i `observations.key`-ordning. Lärosäteskod översätts till metadatanamn och `uni:1` blir Riket.
- Ämnesvägen behålls hel (studieform, ämnesområde, ämnesdelområde, ämnesgrupp). Åldern blir `aldersgrupp`, utom källans Total.
- Kön och värdetext lämnas oförändrade.
- Lärosätena sorteras och dimensionerna läggs i den ordning de först förekommer.
- Torrkörning offline: alla **231/231** chunkhashar och hela manifestet är lika med servermanifestet. Manifestets jsonb-hash återskapades exakt: `432e33a3e6e80e993143183a5883fa85220b5345293469acdd6ffb4ddfaf8286`.
- Vid publicering används `uka_verified_start`, som vägrar ett annat manifest och här svarade `resumed:true`. Därefter läser skriptet `received_indices`, skickar bara saknade index och anropar `uka_verified_finalize`.
- Tester: `python -m unittest tests.test_uka_hst_publish_verified` ger 7 OK. De täcker manifestavvikelse, ändrat värde, glesa mottagna index, återstart som hoppar över mottagna chunkar, vägran vid ny import samt spärr mot referensmaterial och ogiltiga värden.

## Fullföljande
- När uppladdaren startade (11:21:51 UTC) hade servern redan 174 chunkar. En annan, samtidig uppladdning med samma manifest hade skickat 154 och 156–173 mellan 11:17 och 11:21. Den skickade också finaliseringen.
- Den här körningen skickade 174–230 (57 chunkar). Dess eget finaliseringsanrop fick låstimeout (55P03), eftersom den andra processens finalisering pågick under samma lås.
- Servern verifierade 231 delar, 1 151 372 rader och täckning för 120 kombinationer av period, kön och ålder. Därefter aktiverades batchen atomiskt: `published_at` och `activated_at` är 2026-11-10 11:24:24 UTC. Körning `7bec8287-d23e-471f-aeff-ca7d6e268504` har status succeeded.

## Kontroller efter aktivering
- Aktiv HST är `5c6a7d55-8337-4ebc-8e13-5b8b28218e09`. Rollback-batchen `60e861fa-11eb-4db1-8d83-75b4b53e49ad` finns kvar med 1 151 372 rader.
- Paketet jämfört mot den nya batchen: 1 151 372 identiteter i båda, 0 bara i paketet, 0 bara i databasen och 0 värdeavvikelser vid decimaljämförelse.
- `agg_uka_university` för uka-hst har 1 151 372 rader och 10 perioder.
- Utbildningssidans begränsade läsväg (`uka_education_slice`, publik nyckel) ger Riket 2025/26 Total 341 246,6 och LTU 8 587,5 (30 rader per lärosäte). Sidan visar 341 246,6 för Riket, utan konsolfel.
- Övriga 15 aktiva UKÄ-batchar är oförändrade. Indikator 99 är fortsatt `be0322b3` (19 595 rader) och rollback `4892c284` finns kvar (19 595 rader). Legacy-skyddet är oförändrat, och `uka_sync.R` och `etl-uka.yml` är inte ändrade.

## Rollback
Sätt `uka_active_batches.active_batch_id` för `uka-hst` till `60e861fa-…` och kör `agg_refresh_uka()`. Det kräver ett separat godkännande.

## Källbegränsningar (oförändrade)
`full_source_coverage_verified=false` och `source_release_verified=false`. Varje detaljcell är inte oberoende jämförd mot ett JSON-blad, och ingen officiell, oföränderlig källversion är fastställd. Godkännandet upphäver inte dessa begränsningar.
