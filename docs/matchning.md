# Matchning

`/omraden/arbetsmarknad/matchning` visar SCB:s regionala matchningsindikator E3,
TAB6929. Norrbotten är förval via `src/config/geo.ts`; geografin sparas i URL:en.

## Läsmodell och källa

Sidan läser förberäknade, offentliga SCB-aggregat via `matching.functions.ts`,
exporterat genom `aggregates.functions.ts`. Ingen läsning av råa observationer,
inga personuppgifter och inga externa SCB-anrop vid sidladdning.
Katalogen ligger i `src/data/matching/catalog.json`. Komprimerade filer med
innehållshash i namnet ligger i `public/data/matching` och läses via ASSETS.
Svaren begränsas till vald utbildning/kön, en rangordning eller en geografisk
jämförelse. Stora källsvar skickas aldrig till webbläsaren.

Samtliga 312 geografier, alla tillgängliga år, utbildningsgrupper, nivåer,
inriktningar och kön ingår i översikten. Alla åtta E3-mått bevaras. Geografierna
hämtas direkt, även riket och länen. De konstrueras inte genom kommun- eller
länssummeringar.

Utbildning–branschflöden visar A–D (helt, delvis och inte matchade anställda,
samt anställda utan tillräckliga yrkesuppgifter). De omfattar samtliga
utbildningar, kön och år för riket, alla län och Norrbottens 14 kommuner.
Övriga kommuner har full översiktsdata men hänvisas till länet för branschflöden.
E3 innehåller ingen dimension för enskilda yrken; sådana flöden visas inte.

## Tolkning

Populationen är folkbokförda 20–69 år (nattbefolkning). Förvärvsgrad (justerad)
är SCB:s (A+B+C)/E och matchad förvärvsgrad A/E. E utesluter egenföretagare,
studerande och anställda utan tillräckliga yrkesuppgifter. Sidan använder SCB:s
publicerade procenttal, inte kvoter av CKM-justerade antal.

Totalen för specifika utbildningsgrupper har en annan avgränsning än totalen
för utbildningsnivåer eller inriktningar. Dessa indelningar summeras aldrig
tillsammans. Totalgrupper utelämnas ur utbildningsrangordningen.

Null bevaras och visas som ”Uppgift saknas”, även i tabeller och CSV. Luckor
i tidslinjer binds inte ihop. SCB:s regler för publicering av andelar och
CKM-metoden beskrivs på sidan tillsammans med originalnoterna. CKM-delar
kan avvika från totalen; flödesbanden beräknar ingen ny total.

## Uppdatering och kontroller

`scripts/fetch_rmi_matching.py` kontrollerar SCB-metadata innan hämtning.
Workflowet `etl-rmi-e3-view.yml` kontrollerar veckovis, onsdag 06:15 UTC,
och gör en full revisionshämtning kvartalsvis. `workflow_dispatch` kan tvinga
omhämtning. Begäranden begränsas till högst en start varannan sekund och
högst tre samtidiga hämtningar. Avbrutna hämtningar kan återanvända lokala
checkpoints bundna till metadata och exakt urval.

Alla urval och cellantal kontrolleras innan en ny katalog skrivs. Filnamnen
innehåller innehållshash. En misslyckad hämtning publicerar ingen commit;
föregående publicerade version ligger kvar. Schemats kodväg kräver inga
databasändringar eller nya hemligheter.

Kontroller:

- `python -m unittest discover -s tests -p 'test_matching_snapshot.py'`
- `npx tsc --noEmit`
- `npm run build`

Snapshotkontrollerna verifierar varje filhash, full täckning av geografi,
utbildning, kön och år, saknade värden, måttens intervall och att periodfilerna
är identiska med respektive geografis värden.
