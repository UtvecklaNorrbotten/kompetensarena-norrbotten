# HST indikator 33 – läskontroll inför återstart (inga ändringar gjorda)

## Resultat: återstart går inte i nuvarande sandbox

| Underlag | Status |
|---|---|
| `UKA_HST_2016-17_2025-26_2026-11-09.zip` (sha256 2e65e8cd…1ccd1c, 165 606 969 byte) | **Saknas.** Inte i uppladdade filer (där finns bara UKÄ 99-ZIP:en, en pptx och en md), inte i /tmp, inte i Files och inte i projektet |
| Uppackad `hst-collection/hst-full.sqlite` | **Saknas.** Sökning efter `*hst-full*` gav inga träffar |
| Chunkfiler och normaliserade payloads | **Saknas.** /tmp rensades när sandlådan startade om (10:40 UTC) |
| Uppladdningsskript för HST | **Finns inte i projektet.** `scripts/` innehåller bara `uka_99_publish_verified.py` (låst till indikator 99, `uka99_*`) och HST-skript för källhämtning/staging (`uka_hst_full_csv.py`, `uka_hst_csv_staging.py` m.fl.), inget som anropar `uka_verified_*` |
| Pågående process | **Ingen.** Ingen python-, curl- eller uka-process körs |
| Projektfixtur `tests/fixtures/uka-hst-bulk-2026-11-06.zip` | Finns, men är bara pilotens 7 CSV-filer. Den **får inte** användas som underlag |

## Servermanifest (läst, inget ändrat)

- import_key `uka-hst-2026-11-09-2e65e8cd1e34`, batch `5c6a7d55-8337-4ebc-8e13-5b8b28218e09`, skapad 2026-11-10 06:52 UTC
- manifest_hash `432e33a3e6e80e993143183a5883fa85220b5345293469acdd6ffb4ddfaf8286`
- archive_sha256 stämmer med det angivna paketet. Manifestet har 231 chunkar, var och en med index, antal rader och sha256 (5 000 rader/chunk), samt täckning per period/kön/ålder, dimensioner och lärosätesnamn, version 1
- previous_batch_id `60e861fa-11eb-4db1-8d83-75b4b53e49ad` (nuvarande aktiv HST behålls för rollback)
- Databasfunktioner som finns: `uka_verified_start`, `uka_verified_chunk(p_import_key, p_index, p_payload)`, `uka_verified_status`, `uka_verified_finalize(p_import_key)`. Varje chunk kontrolleras mot sin sha256 i manifestet. Startfunktionen för den generella vägen finns inte i projektets migrationsfiler, bara i databasen

## Varför inget exakt återstartkommando kan anges

Chunkarnas sha256 i servern gäller exakta payload-texter som skapades av en normalisering som inte längre finns kvar. För att fortsätta från chunk 155 utan att börja om måste samma normalisering köras på samma `hst-full.sqlite` och ge byte-identiska chunkar 0–154. Det kan kontrolleras mot manifestets hashar innan något skickas. Utan ZIP:en och utan skriptet finns inget att köra.

## Vad som behövs för en senare återstart (separat godkännande)

1. Ladda upp originalpaketet igen. Därefter kontrolleras sha256 och storlek, samt checksums.json i paketet, utan nätverk.
2. Ta fram uppladdningsskriptet: antingen hittas det i GitHub/annan gren, eller skrivs `scripts/uka_hst_publish_verified.py` efter mönstret i `uka_99_publish_verified.py`, med generiska `uka_verified_*`-anrop och utan ny källhämtning.
3. Torrkörning: alla 231 lokala chunkhashar och hela manifestet (hash `432e33a3…`) måste matcha servern exakt. Vid minsta avvikelse avbryts allt och inget skickas.
4. Först därefter skickas bara de chunkar som saknas (155–230) enligt `uka_verified_status`, följt av `uka_verified_finalize`, aggregatomräkning och kontroll.

Förväntat kommando när steg 1–2 är klara (finns inte än):

```text
python scripts/uka_hst_publish_verified.py \
  --root <uppackat paket> --archive <ZIP> \
  --archive-sha256 2e65e8cd1e34ebbf67341a3fc472280af47b932dba693b16225ca08a9f1ccd1c \
  --archive-bytes 165606969 --expected-rows 1151372 \
  --import-key uka-hst-2026-11-09-2e65e8cd1e34 --resume [--publish]
```

Inga skrivningar, commits, uppladdningar, aktiveringar eller källhämtningar har gjorts.
