# Sysselsättning

Sida: `/omraden/arbetsmarknad/sysselsattning`. Norrbotten är förval via `config/geo.ts` och geografi delas i URL:en. Befintlig ämnesrutt och områdeskonfiguration används. Sidan återanvänder Län och kommuns karta, gemensam axelskala och mönstret med avgränsade serverfunktioner via `aggregates.functions.ts`.

## Inventering och urval 2026-11-26

Befintlig databas-ETL i `scripts/etl_scb_bas.py` importerar TAB3784 och TAB2597 för riket, alla 21 län och 290 kommuner, tre könskategorier och båda geografiska perspektiven. Den behålls oförändrad. Företagsregistrets storleksklasser används inte.

Den nya publika läsmodellen innehåller färdiga offentliga SCB-aggregat, inte råa observations- eller företagsregistertabeller. Data hämtas före publicering; inga SCB-anrop görs vid sidvisning.

| Tabell | Innehåll | Referensperiod | Bevarade dimensioner |
| --- | --- | --- | --- |
| TAB3784 | BAS preliminärt antal efter bransch | Månad 2020M01–2026M08 | 15–74 år, samtliga SNI-grupper inklusive okänd och total, kön, arbetsplats/bostad |
| TAB2597 | BAS preliminärt antal efter sektor | Månad 2020M01–2026M08 | 15–74 år, åtta sektorkategorier, kön, arbetsplats/bostad |
| TAB6260 | BAS preliminär arbetsmarknadsstatus | Månad 2020M01–2026M08 | Samtliga publicerade åldersgrupper med födelseregion totalt; separat födelseregionsuppdelning för 15–74 år; kön; antal, befolkning och publicerad sysselsättningsgrad |
| TAB6666 | BAS preliminär arbetsmarknadsstatus efter utbildning | Månad 2020M01–2026M08 | Fast 20–64 år, sex utbildningsnivåer inklusive okänd, kön; antal, befolkning och sysselsättningsgrad |
| TAB3204 | BAS slutligt årligt register efter bransch | År 2020–2024, november | 15–74 år, alla SNI-grupper, kön, arbetsplats/bostad |
| TAB3260 | BAS slutligt årligt register efter sektor | År 2020–2024, november | 15–74 år, alla sektorkategorier, kön, arbetsplats/bostad |
| TAB1786 | BAS slutligt årligt register efter utbildning | År 2020–2024, november | 15–74 år, sex utbildningsnivåer, SNI totalt, kön, arbetsplats/bostad |
| TAB900 / TAB3039 | RAMS äldre metod, dag/natt | År 2011–2018 | 16+ år, alla källans breda SNI-grupper, kön och officiella totaler |
| TAB5837 / TAB5776 | RAMS ny metod, dag/natt | År 2019–2021 | 16–74 år, alla källans breda SNI-grupper, kön och officiella totaler |

Samtliga uttag omfattar riket, alla län och alla kommuner. Födelseregion är totalt i bransch-, sektor- och utbildningsuttagen. Födelseregion och ålder kan inte korsas fritt i gränssnittet; deras egna uppdelningar visas separat. Utbildningsvyn håller åldersgränsen 20–64 genom hela månadsserien, trots att källan också erbjuder 20–65 och 20–66. Detta undviker ett åldersbyte i denna jämförelse. Åldersvyn bevarar källans samtliga grupper; flera är överlappande och ska inte summeras. Den fulla kartesiska produkten av alla dimensioner importeras inte.

### Regionala matchningsindikatorer

Befintlig E3-import (TAB6929) avser utbildningsmatchning, U3 (TAB6928) utbildningsflöden. De besvarar andra frågor än hur många som arbetar. Granskad RMI R3a (TAB5458) beskriver dagbefolkning 20–64 år och 15 branschgrupper; R3b (TAB5459) förändringen. R3a har årsdata 2008–2024 men fotnoten anger källbyte till BAS från 2022. Den får alltså inte användas som en metodmässigt obruten långserie. Direkt BAS/RAMS används här, med separata val och åldersangivelser. Ingen dubblerad RMI-serie importeras som om den vore ett nytt jämförbart underlag.

## Mått och metodgränser

- Antal är personer, inklusive företagare. Det är inte antal jobb, anställningar eller arbetade timmar.
- Nattbefolkning: sysselsatta med bostad i området. Dagbefolkning: sysselsatta med arbetsställe i området. BAS avser folkbokförda; utlandsboende inpendlare täcks inte fullständigt.
- Sysselsättningsgrad är SCB:s publicerade andel av befolkningen i samma grupp. Både täljare och nämnare hämtas för verifiering. Graden visas endast i arbetsmarknadsstatusens bostadsperspektiv.
- Bransch-/sektorsandel är antal i kategorin delat med källans total för samma period, kön, geografi och perspektiv. Den är inte sysselsättningsgrad. Utbildningstabellen saknar egen total; dess andelsval är därför avstängt.
- Förändring i antal respektive procent avser samma månad året före eller föregående år för årsdata. Nollnämnare ger saknad procentuell förändring, inte oändlighet. Förändringar av andelar i procentenheter blandas inte med procentuell antalsförändring.
- Alla serier hålls separata per metod, statistikstatus, referensperiod och geografiskt perspektiv. Inga årsförändringar räknas mellan separata underlag. RAMS äldre serie börjar 2011 för att inte överbrygga metodändringen för äldre vid 2011; 2019 har egen serie. BAS och RAMS överlappar 2020–2021 men länkas inte. Minst tio obrutna jämförbara år finns därför inte ännu för BAS. Kalenderhistoriken når 2011 med separata serier.
- Preliminära BAS-månader och slutliga årliga register är olika underlag. Årligt register avser november, inte årsgenomsnitt. Månadsvärden är inte säsongrensade. BAS årsregister har dessutom ändrade dataleveranser från 2022 och justerad definition för egenföretagare från 2024. Linjen delas i separata segment vid båda gränserna. Förändring 2021→2022 och 2023→2024 visas inte. Årsregistrets personindelningar avser 31 december och sysselsättning/arbetsställe november.
- Offentlig förvaltning överlappar staten, kommun och region. Näringslivet är källans sektorkategori, ingen konstruerad exakt privat/offentlig dikotomi. Raderna summeras inte.
- RAMS-tabellernas kön och SNI har eliminering. Totalerna hämtas från SCB i separata uttag med en eller båda dimensionerna utelämnade. Detaljcellernas summa används inte som officiell total.

## Import och drift

`scripts/fetch_employment.py` använder Python-standardbiblioteket och SCB API v2. Fulla JSON-stat-svar kontrolleras mot begärda koder, dimensionsordning, cellantal, ändliga icke-negativa tal och SCB-version. Glesa värden och statuskoder bevaras. Numeriska värden med status används konservativt inte i beräkning; tabellen visar statuskoden utan att gissa sekretessorsak.

Källdata cachas efter versionsdatum och exakt query, så en avbruten körning kan fortsätta utan att blanda versioner. Högst tre samtidiga API-uttag. Branschens månadsuttag delas i block om högst 140 000 celler. Övriga månadsuttag görs en månad i taget efter att större sektoruttag gett SCB-serverfel. Sektorns månadsdata läses från SCB:s färdiga CSV-ZIP (Windows-1252, strömmande läsning) och kontrolleras dessutom mot ett oberoende API-prov för första och sista månaden, riket, Norrbotten och Luleå. Arkivets SHA-256 sparas när denna väg används. Symboler i CSV-filen bevaras som källstatus; noll förblir noll. Källans version verifieras igen efter respektive tabell. Täljare/nämnare verifieras mot publicerad sysselsättningsgrad med tolerans för avrundning; små nämnare används inte i denna kvotkontroll.

Alla nya filer skrivs först när samtliga tabeller verifierats. Innehållshashade geografifiler och periodfiler ligger komprimerade i `public/data/employment`; katalog med versionsdatum, urval, fotnoter, filhashar och kontrollantal i `src/data/employment/catalog.json`. En Git-commit publicerar hela versionen tillsammans. `employment.functions.ts` läser via ASSETS och returnerar en geografi/kön/perspektiv eller en vald geografisk jämförelse, aldrig hela datakuben. Saknade filer ger ett synligt fel.

Workflow `etl-employment-view.yml` kontrollerar metadata dagligen och hämtar hela respektive tabells urval när SCB:s version ändrats, även historiska revisioner. Oförändrade versioner behålls. Manuell `force` hämtar om allt till en ny svarscache; `--resume` kan användas tillsammans med `--force` för att återanvända en befintlig versionsbunden cache. Den befintliga BAS-databasimporten fortsätter som tidigare. Ingen SQL-migration eller ny hemlighet krävs.

```bash
python scripts/fetch_employment.py          # metadata-kontroll och full hämtning av ändrade tabeller
python scripts/fetch_employment.py --force  # revisionskontroll av samtliga underlag
python scripts/fetch_employment.py --sample # verkligt SCB-prov, ingen publicering
python -m unittest discover -s tests -p test_employment.py -v
node --experimental-strip-types tests/employment.test.ts
npx tsc --noEmit
npm run build
```

## Källor

- [BAS, tabeller, kvalitetsdeklarationer och metod](https://www.scb.se/AM0210)
- [Skillnader mellan RAMS och BAS årsregister](https://www.scb.se/contentassets/592dcafe2a3b4e65b8e5434796bab0af/skillnader_mellan_rams_och_bas_arsregister.pdf)
- [RAMS och förändringar 2011/2019](https://www.scb.se/AM0207)
- [RMI R3a metadata och fotnoter](https://statistikdatabasen.scb.se/api/v2/tables/TAB5458/metadata?lang=sv)
- Katalogens `source` länkar respektive tabells metadata; alla urvalskoder och perioder finns i samma katalog.

## Slutkontroll efter återupptaget arbete

2026-11-26: den avbrutna grenen återupptogs efter att bootstrapkörning 45813455783 hade hämtat och verifierat samtliga underlag. Senaste main integrerades utan konflikt. Python-testerna kontrollerade samtliga 4 181 datafilers hash samt geografisk täckning och urval. TypeScript-tester för mått och metodbrott, typkontroll, riktad ESLint och produktionsbygge passerade. Figurens branschrubrik följer nu valt mått och datatabellens jämförelsekolumn visas bara när jämförelse finns.

Slutligt SCB-stickprov passerade för samtliga tolv underlag. Granskning i webbläsare verifierade Norrbottens tidsserie, riksvärden och sysselsättningsgrad efter utbildning. Mobilgranskningen ledde till begränsad tooltipbredd. Produktionskontrollen upptäckte att hela serverpaketet var 72 798 982 byte mot driftmiljöns gräns 67 108 864 byte. UVAS-årgångarna flyttades därför oförändrade från kodimport till publika ASSETS-filer; katalog, värden och UI behölls. Produktionsbygget får nu en storlekskontroll med 60 MiB-budget innan publicering.
