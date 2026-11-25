# Arbetslöshet under Arbetsmarknad

`/omraden/arbetsmarknad` är områdets ingång. Ämnen ligger i `config/areas.ts`, med arbetslöshet på `/omraden/arbetsmarknad/arbetsloshet`. Kommande ämnen får egna komponenter i `components/labour-market` och ansluts till samma ämnesrutt. Ingen ny huvudlayout behövs. Norrbotten är förval och geografin delas via `?geo=`.

## Källor och läsning

Samma originalfiler som den befintliga AF-importen används: `web-sok-lan-kom` och `web-inskrivna-arbetslosa-andel-av-bas`. Den befintliga databasimporten ändras inte. Den kompletterande läsmodellen bevarar BAS-filens parade SOK/AK-fält, som behövs för att kunna beräkna gruppandelar korrekt, samt den längre filens ALTOT/AKTTOT som inte finns i dagens normaliserade indikator.

`fetch_af_unemployment.py` identifierar pivot-cache efter fältnamn (inte cachenummer), läser strömmande och förberäknar publika aggregat. Sidan läser egen versionshanterad lagring; inga externa källanrop eller råa databasobservationer görs vid sidladdning. Som på Län och kommun används filer som förberäknad läsmodell. Katalogen sparar käll-URL, SHA-256, storlek, hämtningstid, perioder, geografier och valideringsutfall. Serverfunktionerna exporteras genom `aggregates.functions.ts` och begränsar varje svar till vald geografi/kön, en månad/grupp/kön eller en månad/geografi.

Alla 290 kommuner, 21 län och riket ingår. Länssummor följer källans länstillhörighet vid respektive tidpunkt. Kommunens kod behålls vid länsbyte. Kända historiska namn matchas mot kodlistan; okända namn stoppar importen.

## Beräkningar och kontroll

- Andel = 100 × SOK / AK för samma månad, grupp, kön och geografi. Inga geografiska medelvärden av andelar.
- Rikets täljare inkluderar BAS-filens restkategori för saknad geografi. Nämnaren kommer från de 290 kommunernas arbetskraft. Detta kontrolleras mot arbetsbokens synliga rikstabell för varje tillgängligt grupp-/könsvärde.
- Antal i BAS-filen kontrolleras mot arbetssökandefilen över hela gemensamma historiken för alla geografier/kön. ALTOT + AKTTOT kontrolleras mot INSAL.
- Utbildningsnivå saknas före 2024-04 enligt arbetsbokens Info-blad. Dessa celler blir null, även om cachen innehåller tekniska nollor.
- Antal för samtliga finns från 1996. Gruppjämförelsernas parade antal/andelar börjar 2023; utbildning 2024-04. Äldre RAMS-andelar fogas inte till BAS-andelar. Äldre grupphistorik finns kvar i befintlig AF-ETL, men ingår ännu inte i denna läsmodell.
- Åldersgränser ändras 2023 och 2026. Källans äldregrupp har äldre etiketter och beskrivs försiktigt i gränssnittet.
- Årsförändring jämför exakt samma kalendermånad föregående år. Skillnader i andel uttrycks i procentenheter. Noll föregående år ger ingen procentuell förändring.
- Rullande medel kräver 12 konsekutiva kända månader, även innan valt visningsintervall. Andelsmedel är tidsmedel av månadsandelar, inte en poolad årsandel. Inga säsongrensningspåståenden.
- Sekretessvärden blir aldrig noll. Saknade eller sekretessmarkerade celler bryter linjer och rullande fönster.

## Uppdateringar

`10 · Data · AF – arbetslöshetens läsmodell` kontrollerar källsidan dagligen. Arbetsböcker laddas bara när båda filer har samma nya månad, vid manuell `force` eller kvartalsvis revisionskontroll den 16 januari/april/juli/oktober. Hela historiken kontrolleras före publicering. Valideringsfel gör att tidigare filer och webbplatsdata behålls. Git push är fast-forward och får misslyckas vid samtidiga ändringar; inga andra arbeten skrivs över. Läsmodellen behöver inga databasnycklar.

## Kontrollkommandon

- `python -m unittest discover -s tests -p test_af_unemployment.py`
- `node --experimental-strip-types tests/af-unemployment.test.ts`
- `npx tsc --noEmit`
- `npm run build`

NEET/UVAS väntar på separat MUCF-hämtning. SCB:s AKU/BAS-arbetslöshet ersätts inte med AF:s mått.
