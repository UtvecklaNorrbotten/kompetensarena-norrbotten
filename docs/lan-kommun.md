# Län och kommun

Sidan `/omraden/lan-kommun` använder samma layoutprinciper som Utbildning: ett gemensamt filter till vänster, luftiga figurer till höger, historik, topp 5 och datatabell/CSV. Geografin ligger i `?geo=`. Kartan och kommunjämförelsen ändrar samma urval. Norrbotten är förval. Alla 14 kommuner ingår.

## SCB-data och spårbarhet

U3 (TAB6928) hämtas direkt från SCB:s API v2 med explicita värdemängder för län respektive kommun, utbildningsgrupp och kön. Samtliga tillgängliga årsintervall och utbildningsgrupper ingår, kvinnor, män och SCB:s total. Perioderna lagras precis som SCB redovisar dem. Länsvärden hämtas separat. Inget riksvärde konstrueras.

`src/data/rmi/` är versionshanterade, färdigställda publika SCB-aggregat, inte rådata ur applikationens observationslager. Läsningen går genom `aggregates.functions.ts`. Servern lämnar bara en geografi och ett kön, respektive en rad per kommun i jämförelsen. Ett nytt databaslager behövs inte för att publicera denna begränsade tabell. Om omfattningen växer till hela riket kan samma kontrakt flyttas till en agg-tabell utan ändringar i figurerna.

`catalog.json` innehåller källans uppdateringstid, hämtningstid, dimensioner och originalnoter. Skriptet kontrollerar antal celler, datatyper och geografisk täckning. Alla källsvar verifieras innan snapshots skrivs. Null bevaras. Workflowet kontrollerar metadata på tisdagar och gör en full revisionshämtning kvartalsvis. Jobbet kräver inga databashemligheter. Ett misslyckat jobb publicerar inga förändringar.

## Tolkning

Delflödena överlappar. Därför används sex separata staplar med gemensam skala, inte ett Sankeydiagram som antyder att samma individer kan följas mellan kategorier. Netto är ett separat källvärde. Det räknas aldrig fram genom att subtrahera eller summera komponenter. SCB:s definition av utflyttade inkluderar avlidna. Åldersutträden är inte pensionsavgångar. Särskild metodnot visas för 2023–2024 där utbildningsklassificering påverkar publiceringen. Null visas som ”Uppgift saknas”, aldrig noll.

Kartan visar urval, inte en färgskala för statistik. Samtliga kommunpolygoner och innerringar bevaras vid projektion till SVG. Geometri: [okfse/sweden-geojson](https://github.com/okfse/sweden-geojson/blob/master/swedish_municipalities.geojson), hämtad 2026-11-25. Kartan är orienterande; källans generaliserade gränser är inte avsedda för fastighets- eller gränsbestämning.

## Kontroll

- `python -m unittest discover -s tests -p 'test_rmi_snapshot.py'`
- `npx tsc --noEmit`
- `npm run build`
