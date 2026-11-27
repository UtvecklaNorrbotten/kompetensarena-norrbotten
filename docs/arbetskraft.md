# Arbetskraft

Sida: `/omraden/arbetsmarknad/arbetskraft`. Norrbotten är förval och geografin delas via `?geo=`. Matchning och pendling utvecklas separat. Inga mikrodata, modellvärden eller konstruerade prognoser används.

## Återupptaget arbete

Det avbrutna arbetet hade ingen sparad arbetskraftsgren eller PR. Den 27 november 2026 återupptogs uppdraget från aktuella main. Befintliga komponenter och läsmodeller för sysselsättning, kommungeografi återanvänds. BAS-databasimporten och de andra arbetsmarknadssidorna behålls.

## Källor och avgränsningar

| Underlag | Mått och dimensioner | Geografi och tid |
| --- | --- | --- |
| BAS TAB6260 | Alla publicerade arbetsmarknadsstatusar, befolkning och andelar; kön; 15–74 och 20–64 år. Separat födelseregion för 20–64 år. | Riket, samtliga län och kommuner. Månad från 2020. |
| BAS TAB5655 | Samtliga publicerade åldersgrupper, kön och arbetsmarknadsstatusar. Födelseregion totalt. | Riket, län och kommuner. Preliminära årsmedelvärden från 2020. |
| BAS TAB6666 | Arbetskraft, personer utanför, befolkning och publicerat deltagande efter sex utbildningsnivåer inklusive okänd, kön, fast 20–64 år. | Riket, län och kommuner. Månad från 2020. |
| Yrkesregistret TAB4435 | Antal anställda efter treställig SSYK, ålder och kön. Egna företagare ingår inte. | Arbetsplatsens län och riket, 2020–2024. Kommunuppgifter finns inte i denna tabell. |
| RMI U4 TAB6371 | Antal och publicerad andel förvärvsarbetande 60–64 år, samt samtliga 20–64 år, efter utbildning och kön. Separata utbildningsindelningar. | Arbetsplatsens län och riket, 2019–2024. FA-regioner ingår inte i sidans urval. |
| BAS TAB5543 | Sysselsatta efter bransch, kön, 15–74, 55–64 och 65–74 år. Yrkesställning/födelseregion totalt. | Endast riket, arbetsställets belägenhet, årligt register 2020–2024. Får inte visas som regional data. |
| RMI U1b TAB6368 | I arbetskraften, inte i arbetskraften och totalt antal personer, efter utbildningsgrupp/nivå/inriktning och kön; 20–64 år. | Bostadens län och riket, 2019–2024. Eget arbetskraftsmått som kombinerar förvärvsarbetande med inskrivna arbetslösa hos AF. |

BAS arbetskraft = sysselsatta och arbetslösa. RMI U1b använder förvärvsarbetande och inskrivna arbetslösa hos AF, med egen avgränsning, och är därför separat från BAS. RMI U1b har enbart publicerade antal i tabellen; inga härledda deltagandeandelar konstrueras. Arbetskraftsdeltagande använder SCB:s publicerade kvot med befolkningen i samma grupp som nämnare. AF:s inskrivna arbetslösa ersätter inte BAS arbetslösa. Studerande, pensionärer, sjuka och övriga utanför arbetskraften visas var för sig. Personer utanför arbetskraften är inte automatiskt tillgängliga för arbete.

Ålderspyramiden visar årsmedelvärdet av arbetskraften, män och kvinnor, i tolv icke överlappande femårsgrupper från 15–19 till 70–74. Den följer sidans geografi och har eget referensår. Breda och överlappande åldersgrupper visas aldrig som pyramidstaplar.

Äldre per bransch kan inte beläggas regionalt med den valda öppna BAS-tabellen. Riket anges därför uttryckligen. Yrkesregistret och U4 visar länet om användaren valt en kommun, med synligt besked och egen figurgeografi. Det ursprungliga kommunvalet bevaras för övriga avsnitt.

U4:s namn och fotnot talar om förväntade åldersavgångar. Här beskrivs det som observerad åldersstruktur. Pensionstidpunkt, framtida sysselsättning och faktisk ersättningsrekrytering är okända.

## Jämförbarhet

- BAS börjar 2020; tio jämförbara BAS-år finns ännu inte. Äldre RAMS eller AKU fogas inte in som om de hade samma definition.
- Månader är preliminära och inte säsongrensade. TAB5655 är medelvärden av månader, inte december eller november.
- U1b och U4 har RAMS/BAS-brott 2022. Yrkesregistret har modellimputerade yrken och utökad åldersgräns 2023, samt förändrad företagaravgränsning 2024. BAS årsregister TAB5543 har förändrad företagaravgränsning 2024. Linjer delas och förändringar över respektive gräns spärras.
- Registerperspektiv, årsmedelvärden, RMI:s och BAS arbetskraft är separata underlag. RMI:s nivå, inriktning och utbildningsgrupp har olika totaler och visas separat.
- Saknade värden och källstatus bevaras. Tal med status används inte i diagram eller beräkningar. Nollvärden bevaras. Publicerade totaler/andelar ersätts inte av summerade skyddade delceller.

## Import och drift

`scripts/fetch_workforce.py` återanvänder sysselsättningsimportens HTTP-klient, JSON-stat-validering och komprimeringsformat. Varje svar kontrolleras mot exakt urval, dimensionsordning, cellantal, taltyp och källversion. Svarscache och kontrollpunkter binds till tabellversion och urval. Metadata kontrolleras igen efter hämtning. Publicerade BAS-deltaganden kontrolleras mot källans arbetskraft och befolkning för tillräckligt stora nämnare, med tolerans för skydd och avrundning.

Katalog och hashade filer skrivs efter att alla underlag lyckats. En Git-commit publicerar hela versionen. Geografi- och periodfiler ligger i `public/data/workforce`; de läses via ASSETS och avgränsade serverfunktioner, exporterade från `aggregates.functions.ts`. Katalogen ligger i `src/data/workforce/catalog.json`. Stora observationstabeller ingår inte i Worker-koden. Ingen SQL-migration eller Lovable-agent behövs.

`etl-workforce-view.yml` kontrollerar metadata dagligen 09:45 UTC och hämtar om hela urvalet för ändrade källversioner, även historiska revisioner. Manuellt `force` använder ny svarscache. GitHub Actions bevarar versionsbunden cache mellan körningar. Källa med oförändrad version återanvänds bara om publicerade filer finns.

```bash
python scripts/fetch_workforce.py
python scripts/fetch_workforce.py --sample  # verkligt API-prov, ingen publicering
python scripts/fetch_workforce.py --force
python -m unittest discover -s tests -p test_workforce.py -v
node --experimental-strip-types tests/workforce.test.ts
npx tsc --noEmit
npm run build
```

GitHub Actions gör även ett oberoende SCB-stickprov för första/sista period och valda kategorier i varje underlag. Webbläsarkontrollen använder den riktiga sidan och serverfunktionerna: kommunval i URL, BAS-grupper, publicerat deltagande efter utbildning, uttryckligt läns-/riksbyte när kommundata saknas, ålderspyramid, datatabell, CSV och mobilbredd.
