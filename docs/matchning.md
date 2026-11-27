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

## Matchningskartan – undersida

`/omraden/arbetsmarknad/matchning/matchningskarta` visar SCB:s nationella
kombinationer av utbildning och yrke. Länken från matchningssidan tar med
vald utbildningsgrupp. Kartans mer detaljerade utbildningsindelning behålls:
om en E3-grupp innehåller flera utbildningar väljs den första med synlig
upplysning om uppdelningen; användaren väljer annan del i utbildningslistan.
Totaler, nivåer och inriktningar överförs inte som en specifik utbildning.

Besökaren växlar mellan utbildning till yrken och yrke till utbildningar.
Urvalet sparas i URL:en (`direction`, `code`, `group`). Tio resultat visas
först; ”Visa alla” visar hela urvalet. Nollandelar finns ett ytterligare klick
bort och saknade andelar behålls som saknade. Även ett urval med färre än tio
resultat kan öppna nollandelarna. Hela rader färgas efter huvudkategori;
bedömningens inriktning och nivå visas i text och kategorin finns för
skärmläsare. Ingen kvantitativ stapel visas.

Sortering: helt matchad, delvis matchad, inte matchad; därefter originalandel
fallande, svenskt namn och kod. Saknad andel sorteras sist inom sin kategori.
Ingen egen rangordning görs mellan underkategorierna av delvis matchning.
Andelen byts med riktningen: yrkesandel inom utbildning respektive
utbildningsandel inom yrke. Andelarna normaliseras aldrig om; utbildningarna
kan täcka mindre än hela yrket. Geografin är alltid hela Sverige och
statistikår skiljs från bedömningsår. Riksandelar presenteras aldrig som lokala.

### Hämtning och läsmodell

`scripts/fetch_rmi_matching_map.py` hittar Excel-länken på SCB:s RMI-sida och
hämtar filen till minnet. SHA-256 upptäcker förändringar även om adressen
behålls. Oförändrad fil ger ingen datacommit. Vid ändring kontrolleras
kolumndefinitioner, år, kategorier, entydiga koder, unika kombinationer,
andelarnas intervall och full kombinationstäckning före publicering.
Okända bedömningar eller ändrat schema stoppar publiceringen.

Endast långformatets koder, namn, koppling till E3-grupp, båda andelarna,
ämnes- och nivåbedömning samt definitioner och källmetadata sparas.
Nollandelar bevaras eftersom bedömningen fortfarande är användbar.
Andelar lagras i originalprecision, inte visningens avrundning.
Excel-fil, färger, bilder och dubblerade matrisblad sparas inte.

Katalog: `src/data/matching-map/catalog.json`. Matrisen är gzip-komprimerad
med innehållshash i `public/data/matching-map`; serverfunktionen
`matching-map.functions.ts` läser via ASSETS och returnerar bara valt yrke
eller vald utbildning (högst en rad per motgrupp). Komponenten läser aldrig
hela matrisen eller SCB:s API. Äldre matrisfiler tas bort vid en ny
verifierad hämtning; Git-historiken bevarar tidigare publicerade versioner.

Workflow: `etl-rmi-matching-map.yml`, onsdag 06:45 UTC och manuellt med
valbar tvingad omhämtning. Inga paket utanför Pythons standardbibliotek,
hemligheter eller databasändringar behövs. Valideringsfel stoppar commit;
föregående publicerade katalog ligger kvar.

Kontroller:

- `python -m unittest discover -s tests -p 'test_matching_map.py'`
- `node --import tsx tests/matching-map.test.ts`
- `npx tsc --noEmit`
- `npm run build`

Första hämtningen 2026-11-27: 13 395 kombinationer, 95 utbildningar,
141 yrkesgrupper, statistikår 2024 och bedömningar från Trender och
prognoser 2023. [SCB:s RMI-sida](https://www.scb.se/AM9906) är
beständig källänk; direktlänken till aktuell arbetsbok sparas i katalogen.
