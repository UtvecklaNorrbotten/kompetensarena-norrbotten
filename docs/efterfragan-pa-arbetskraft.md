# Efterfrågan på arbetskraft

Sida: `/omraden/arbetsmarknad/efterfragan-pa-arbetskraft`. Norrbotten är förval via `config/geo.ts`; geografi ligger i URL:en. Områdeskonfiguration och befintlig ämnesrutt används. Övriga områdessidor och befintlig databas-ETL ändras inte.

## Inventering och källval 2026-11-25

Den befintliga AF-månadsimportens källregister (`R/etl/af_sources.R`) innehåller arbetssökande, tid utan arbete, svag konkurrensförmåga, arbetslösa per yrkesområde och BAS-andelar. Det innehåller inte platsstatistik. Yrkesbarometern finns separat, inklusive relationstabeller till SSYK; den mäter bedömda jobbmöjligheter/efterfrågan och är inte ett annonsregister. Arbetslöshetens och Län och kommuns versionerade läsmodeller, serverfunktionsmönster, geografier, kartkomponent och axelskala återanvänds.

| Källa | Innehåll och faktisk historik | Användning |
| --- | --- | --- |
| AF `web-platser` | Nya/kvarstående platser, alla varaktigheter respektive mer än tio dagar; totaler 1996-01–2026-10 | Tidsserie, 12 månader, säsong, geografisk jämförelse |
| Samma arbetsboks yrkesområdescache | AF-yrkesområde, kompetenskrav, sommarjobb; från 2013-01 | Områdesfilter, rangordning och förändring |
| Samma arbetsboks SNI-cache | SNI 2007-avdelning, sommarjobb; från 2010-01 | Bevarad dimension för framtida analys |
| AF `web-allajobb-yrkesomrade` | KVAR, AF-yrkesområde, SSYK 2012 fyrsiffrig kod, yrkesbenämning och sommarjobb; faktisk cache 2021-01–2026-10 | SSYK-filter, rangordning och geografier. Källsidan anger 2020 men filen börjar 2021. |
| SCB LoR TAB6606 | Fem typer av lediga jobb, region, kvartal; antal, marginal och årsförändring; 2024K2–2026K2 | Separat kvartalsserie med felstaplar, län/riket |
| SCB LoR TAB6989 | Personer som saknas, SSYK-yrkesområde och regionala grupperingar, år, antal och marginal; 2024–2025 | Separat yrkesområdesjämförelse och osäkerhetstabell |
| JobTech Historical Ads | Avpublicerade Platsbankenannonser, API från 2016, bulkfiler även från 2006 | Faktisk, reproducerbar annonsgranskning; ännu inget månatligt UI-mått |
| JobTech JobSearch/JobStream | Aktiva annonser respektive förändringsflöde | Behövs tillsammans med historik för en framtida komplett publiceringsserie |
| JobAd Links | Annonser från externa aktörer | Blanda inte med Platsbanken utan överlapps- och täckningskontroll |

AF-filerna innehåller riket, samtliga 21 län och 290 kommuner. Län följer respektive källrads län; rikets restkategori utan geografi behålls. Kommuner med samma kod behålls genom historiska namn- och länsbyten. Originalkällornas geografier och klassificeringar används, ingen automatisk koppling mellan AF-yrkesområden och LoR:s ensiffriga SSYK konstrueras.

## Mått och jämförbarhet

- En annons är en publicering. Antal annonserade tjänster är annonsens angivna `number_of_vacancies`. Ingetdera är en fullständig skattning av ekonomins alla lediga jobb.
- AF:s nya platser är ett månadsinflöde. Kvarstående är sökbara platser vid månadens slut. Rullande **summa** används för inflöden och **medel** för bestånd. Båda kräver tolv konsekutiva kända månader; ingen säsongsrensning påstås. Rullande summa beskriver anmälda platser och kan innehålla samma tjänst flera gånger.
- Den långa filens `NYATOT`, `KVARTOT`, `NYA`, `KVAR` bevaras var för sig. Yrkesfilen har bara `KVAR`. Eftersom dess rubrik inte preciserar varaktighet visas den som **yrkesfilens avgränsning**, utan att ange att den är identisk med den långa filens valbara varaktighetskategorier.
- Yrkesfilens KVAR-summa stämmer inte exakt med den långa filens KVAR. Alla differenser per månad sparas i katalogen och gränssnittet beskriver att underlagen inte ska summeras eller behandlas som identiska. Varken klassificerade delmängder eller källor tvingas till lika totaler.
- Saknad kombination är inte noll. Sekretess `<5` förblir en separat markering och propageras vid summering. Okända värden bryter rullande fönster. SCB:s undertryckta osäkra skattningar visas som uppgift saknas, utan ett obestyrkt påstående om sekretess. SCB-status bevaras i källsvaret.
- AF:s rättning av maj 2026 (2026-06-16) gällde dubbla registreringar. Vi använder aktuell reviderad källa. Aggregaten innehåller inga annons-id, vilket utesluter egen individannonsbaserad deduplicering eller en exakt kontroll av flera arbetsorter.
- LoR mäter även jobb utan annons. LoR:s kvartalsstatistik börjar 2024K2; KV länkas inte på grund av metodbrottet. Antal och marginaler är avrundade till hundratal. Personer som saknas per yrke är ett separat mått, för arbetsställen med minst fem anställda. LoR har inga kommunvärden i dessa tabeller; kommunval visas därför uttryckligen med sitt län i denna separata del.

## JobTech-granskning

`scripts/audit_jobtech_demand.py` hämtar alla sidor i ett avgränsat historiskt fönster och stoppar om paginationstaket överskrids. Det filtrerar sedan exakt `start <= publication_date < nästa månad`, eftersom API-svaret inkluderade tre annonser på nästa månads gräns i den genomförda kontrollen. Unika `original_id` skiljs från versions-id. Okänt antal platser blir inte noll. Resultatet sparar SHA-256 för källsvaren men inga annons-id, arbetsgivaridentiteter, texter eller personuppgifter.

Rapport: `docs/data/jobtech-demand-audit-25-2026-09.json`. Granskningen omfattade 1 629 hämtade rader, varav 1 626 var publicerade i september. Dessa hade 1 626 unika original-id och 2 545 angivna tjänster. Inga upprepade original-id hittades. Det fanns 102 kluster (233 annonser) med samma arbetsgivare, normaliserade rubrik, SSYK och kommun. Detta är **möjliga återpubliceringar**, inte verifierade dubbletter. En arbetsgivare kan legitimt rekrytera flera gånger till liknande tjänster. Därför slås dessa kluster inte samman.

Det är ett historikindex vid hämtningstillfället, inte bevis för alla publiceringar under september: fortfarande aktiva annonser saknas. API:s `positions` ändrades från 0 vid limit=1 till ett annat värde vid limit=100 i provet; det används inte som ett tillförlitligt globalt mått. Antal tjänster summeras från de faktiskt paginerade annonserna. `workplace_address` ger en redovisad arbetsort; detta bevisar inte att annonsen bara avser en arbetsort. Externa JobAd Links ingår inte.

## Import och publicering

`scripts/fetch_labour_demand.py` upptäcker AF-filer efter prefix och kontrollerar att båda har samma period. Pivot-cacher identifieras med exakt fältmängd. Okänd geografi, okänd SSYK-struktur, lucka i källans månadsföljd, ofullständigt SCB-svar eller bakåtflyttad publiceringsmånad stoppar jobbet. Fyra mått för alla 370 månader kontrolleras mot den synliga rikstabellen i AF:s arbetsbok; utfallet och källornas differenser sparas i katalogen.

Alla mått, kompetenskrav, sommarjobbsdimension och SNI-avdelning sparas i `public/data/demand/geo-*.json`. Filerna serveras från samma webbplats som statiska resurser, så att de inte förstorar Worker-koden. Serverfunktionen läser dem via Cloudflares ASSETS-bindning (lokalt via samma ursprung). Filerna innehåller deterministisk gzip/base64 av färdiga aggregat, vilket håller storlek och laddning hanterliga. Yrkesbenämningar bevaras som relationer till SSYK och AF-yrkesområde i katalogen; antalen aggregeras över benämning. Käll-URL, SHA-256, filstorlek, start/slutperioder, värdemängder och hämtningstid finns i `catalog.json`. LoR:s samtliga celler, klassificeringar, noter och statuskoder för båda tabellerna bevaras i `lor.json`.

Serverfunktioner exporteras genom `aggregates.functions.ts`. Endast valt urval, en rad per kategori eller en geografisk jämförelse lämnas till klienten. Inga råa `observations`, externa API-anrop vid sidladdning eller databasnycklar behövs.

Workflow: AF:s platsstatistik ingår i `10 · Data · AF – arbetsmarknadsstatistik`. SCB har `10 · Data · SCB LoR – lediga jobb och rekryteringsbehov`, med metadatakontroll dagligen 07:15 UTC (08:15 vintertid, 09:15 sommartid). AF-arbetsböcker hämtas bara vid ny gemensam period, manuell `force` eller den 16 januari/april/juli/oktober för revisionskontroll. SCB hämtas vid ändrad `updated` eller samma revisionskontroll. Fulla kontroller körs innan en enda git-commit publicerar hela ändringen. Push är fast-forward; samtidiga ändringar skrivs inte över.

## Verifiering

```sh
python -m unittest discover -s tests -p test_labour_demand.py
node --experimental-strip-types tests/labour-demand.test.ts
npx tsc --noEmit
npm run build
```

## Fortsatt arbete

En fullständig annonsserie kräver sammanfogning av Historical Ads och aktiva JobSearch/JobStream, stabil versionshantering efter original-id, lokalt halvöppet datumfönster och tätare revisionshämtningar av sent avpublicerade annonser. API-paginering måste delas i mindre datumintervall om taket överskrids. Därefter kan separata mått för annonser, kända annonserade tjänster och andel med okänt platsantal publiceras. Skillnader mot AF:s officiella platsaggregat måste förklaras och flerarbetsortsannonser behöver en uttrycklig fördelningsregel. Ingen obestyrkt exakt deduplicering ska läggas till.

## Primärkällor

- https://arbetsformedlingen.se/statistik/sok-statistik/tidigare-statistik-tidsserier
- https://arbetsformedlingen.se/statistik/sok-statistik/forklaring-av-statistiken
- https://arbetsformedlingen.se/statistik/sok-statistik
- https://historical.api.jobtechdev.se/
- https://data.jobtechdev.se/dataservice/
- https://data.jobtechdev.se/annonser/historiska/
- https://www.scb.se/am0702
- https://www.scb.se/hitta-statistik/statistik-efter-amne/arbetsmarknad/efterfragan-pa-arbetskraft/lediga-jobb-och-rekryteringsbehov/produktrelaterat/fordjupad-information/lediga-jobb-och-vakanser/

## Samordning 2026-11-26

AF:s två platsfiler bearbetas nu i ett oberoende jobb i det befintliga workflowet `etl-af-monthly-check.yml`. Samma AF-källsida och geografihjälpare återanvänds. Jobbet läser båda filernas publiceringsperiod och gör kvartalsvis revisionshämtning; `publish-history` tvingar omhämtning. Övrig AF-databasimport använder fortsatt sina befintliga importer och indikatorer. Fel i ett jobb stoppar inte de övriga jobben. Den tidigare kombinerade workflowfilen `etl-labour-demand.yml` behålls med enbart SCB LoR och eget schema, validering och publicering. `--source af` respektive `--source lor` håller källanrop och skrivningar åtskilda.

LoR:s fyra grupper är förval; nio yrkesområden kan väljas. Alla grupper och båda indelningarnas direktpublicerade skattningar och marginaler sparas. I Norrbotten 2024 saknas antal och marginal för 1/9 respektive 0/4 grupper; 2025 är motsvarande 2/9 respektive 1/4. Grövre indelning löser alltså inte allt bortfall. Andelarna i TAB6989 finns som struktur men publiceras ännu inte av SCB och erbjuds inte i gränssnittet.

## AF:s SSYK-aggregering

AF:s egen KVAR-fil kan visas som fyra kompetensgrupper, nio ensiffriga SSYK-områden eller samtliga fyrsiffriga grupper. Klassificeringen finns i `af-ssyk.ts` och tillämpas på varje förberäknad källrad i serverns läslager. Samma urval kan följas över tid och geografi. Inga LoR-skattningar eller marginaler används i AF-beräkningen. Militära koder med inledande 0 och okända koder (inklusive 9999) bildar två separata restkategorier. De ingår vid avstämning av hela yrkesfilen, men inte som vanliga yrken i de fyra/nio huvudgrupperna. Originalfilens nollor, null och sekretess bevaras; en frånvarande yrkeskombination imputeras inte som noll.

Alla fyrsiffriga grupper finns kvar i filtret och i detaljvyn med sökning på kod eller samtliga bevarade yrkesbenämningar. Benämningarnas gemensamma SSYK visas med full tidsserie; antalet är publicerat på SSYK-nivå och ska inte tillskrivas varje benämning separat. De två grova indelningarna avstäms mot yrkesfilens KVAR för varje månad och geografi i `tests/af-ssyk.test.ts`.
