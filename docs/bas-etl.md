# SCB BAS – månadsuppdatering och kvartalsrevision

## Avgränsning

Två separata indikatorer, båda preliminära och från januari 2020:

| Indikator | PxWeb2-tabell | Dimension |
| --- | --- | --- |
| `bas-sysselsatta-bransch` | `TAB3784` | 15 breda branschgrupper, totalt och uppgift saknas |
| `bas-sysselsatta-sektor` | `TAB2597` | Alla åtta sektorkategorier, inklusive totalt |

Urval: Riket, alla 21 län och alla 290 kommuner; kvinnor, män och totalt;
15–74 år; födelseregion totalt. Båda måtten sparas: sysselsatta efter
arbetsställets respektive bostadens belägenhet. Geografiernas och könens
totaler kommer från SCB; inga egna summeringar används.

BAS räknar personer inklusive företagare, inte antal anställningar eller
arbetade timmar. Bransch och sektor går inte att korsa i dessa tabeller.
Offentlig förvaltning totalt överlappar staten, kommun och region. Kommun
som sektor är en arbetsgivarkategori, inte en geografisk kommun.

## API och datamodell

Klient: `scripts/etl_scb_bas.py`, Python 3.12+, standardbiblioteket.

- Metadata: `GET https://statistikdatabasen.scb.se/api/v2/tables/{table}/metadata?lang=sv`.
- Data: `POST https://statistikdatabasen.scb.se/api/v2/tables/{table}/data?lang=sv&outputFormat=json-stat2`.
- Query: `selection` med `variableCode` och explicita `valueCodes`.
- En månad per SCB-uttag, högst 31 824 celler i nuvarande branschurval.
- JSON-stat dimensionernas index bestämmer ordningen; inga antaganden om
  vilken ordning dimensionerna eller värdena kommer i svaret.
- Null och SCB-status bevaras; saknade värden ersätts inte med noll.

Observationerna använder befintliga `geo_code`, `period` (`YYYYMmm`),
`value` och `dimensions`. Dimensionerna innehåller tabellinnehåll,
geografiskt perspektiv (`arbetsstalle`/`bostad`), kön, ålder, födelseregion,
bransch eller sektor samt statistikstatus. Källans koder och etiketter
bevaras. Metadata lagras via ETL-kontraktet och källstatus via
`scb-bas-industry` respektive `scb-bas-sector`.

Nuvarande fulla urval innebär 46 800 observationer per månad, totalt cirka
3,7 miljoner från 2020M01 till 2026M07. Klienten strömmar en månad åt gången;
hela historiken behöver inte finnas i arbetsminnet samtidigt.

Ingen visualisering eller ny läsning av råa observationer byggs i denna
ändring. Kommande visualiseringar ska följa AGENTS.md och läsa aggregat.

## Månadsflöde

`10 · Data · BAS – månadsuppdatering` körs dagligen 08:45 UTC.

1. Läs vårt eget sparade källtillstånd.
2. Börja kontrollera SCB-metadata den 22:a. Förväntad referensperiod är då
   innevarande månad minus två månader. Den 22:a är ett konservativt
   kontrollfönster, inte ett garanterat publiceringsdatum. Senaste publicering
   var 2026-09-29 för juli och nästa annonserades till 2026-10-27.
3. Fortsätt även efter månadsskiftet tills förväntad period publicerats hos oss.
   Misslyckad hämtning eller pausad kvartalsimport fortsätter också utanför
   ordinarie fönster. Utanför ett aktivt fönster görs inga SCB-anrop.
4. Läs `updated` och tidsdimensionen. Om ingen ny period finns: spara
   `waiting` eller `no_change`; hämta inga observationsvärden.
5. Vid första importen: hämta hela historiken. Därefter hämtas bara månader
   efter `latest_successful_period`, även om flera månader har missats.
6. Nya månader publiceras via `replace_period`. Sparad framgångsmarkör flyttas
   först efter att samtliga planerade perioder har finaliserats. Om markören
   inte kunde sparas spelas perioderna säkert om vid nästa kontroll.

En metadataändring som endast gäller redan importerad historik utlöser inte
fullhämtning i månadsflödet. Dessa revideringar tas med vid kvartalsrevisionen.
Manuellt `check` kontrollerar metadata även utanför fönstret; `full` hämtar
hela historiken; `validate` provar senaste månad utan databasåtkomst.

## Kvartalsrevision och återstart

`20 · Kontroll · BAS – historikrevision` körs den 18 januari, april, juli
och oktober 12:15 UTC. Tiden ligger efter morgonjobben, efter AF:s 1–15-fönster
och före BAS månadsfönster. Båda BAS-workflows har samma concurrency-grupp
och kan inte publicera parallellt. Det låset omfattar BAS, inte manuella
körningar av andra källor.

Hela urvalet hämtas även när metadata är oförändrad. Varje indikator
publiceras som en full snapshot; den gamla versionen är aktiv tills hela
snapshoten validerats och finaliserats atomiskt. Tabellerna kan ha separata
versionsdatum och framgångsmarkörer.

Fulla importer är bundna till en SHA-256-importnyckel med SCB-version,
urval, perioder och chunkstorlek. Vid avbrott sparas staging för återstart.
En delvis sparad månad spelas om och befintliga chunkar checksummeverifieras.
Ändrat SCB-versionsdatum ger en ny snapshot; versioner blandas inte.

En pågående eller misslyckad kvartalsrevision markeras med
`revision_pending`, så månadsworkflowet fortsätter fullimporten nästa dag.
Tidsbudgeten är fyra timmar; budgetstopp markeras som misslyckad/ej klar,
inte som lyckad publicering.

## Driftsättning

1. Applicera `drizzle/migrations/0039_bas_sources_and_indicators.sql` i
   Lovable-databasen. Det är en idempotent registrering av två indikatorer
   och två datakällor. Befintliga geographies för alla kommuner/län/Riket
   och snapshot-/periodbatchfunktionerna ska redan vara installerade.
2. Befintliga GitHub Secrets `ETL_BASE_URL` och `ETL_PUBLISH_KEY` återanvänds.
   Inga nya hemligheter krävs.
3. Starta månadsworkflowet med `mode=full` för första importen, eller `check`
   som också gör fullimport när källan aldrig har importerats.
4. Kontrollera att båda källorna har `succeeded`, rätt senaste period och
   rätt `published_updated` i adminstatusen och workflowrapporten.

Workflows tillämpar inte SQL-migrationer. Saknad registrering ger ett tydligt
fel och flyttar ingen framgångsmarkör. Manuell `validate` och testworkflowet
kan köras redan före databasregistreringen.

## Verifiering

```bash
python -m unittest discover -s tests -p 'test_bas_etl.py' -v
python scripts/etl_scb_bas.py --mode validate
```

Tester använder syntetiska exempel för kalendergränser, väntande och
misslyckade hämtningar, glesa JSON-stat-värden, dimensionsordning, säker
publicering, versionsändringar och återstart. Det separata testworkflowet
gör dessutom ett verkligt uttag för Riket, Norrbotten och Luleå, båda
geografiska perspektiven, alla kön och samtliga bransch-/sektorkategorier.

Rapporter sparas som GitHub Actions-artifacts i 90 dagar och innehåller
ingen autentiseringsinformation. Grön `validate` betyder validerat SCB-prov,
inte publicerad produktionshistorik.
