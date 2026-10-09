# Skatteverket: arbetsgivaravgifter och avdragen skatt

Granskad 2026-10-09. Källundersökning och läsande testworkflows, ingen produktionsimport.

## Bedömning för Kompetensarena

**Tekniskt användbar, men inte ett mått på arbetsmarknaden vid lokala arbetsställen.**
Använd i första hand bruttolön eller lönesumma, med tydlig etikett om arbetsgivarnas
registrerade säte. Använd SCB:s månatliga Anställningar/BAS som huvudalternativ för
sysselsättning. En stigande nominell lönesumma visar inte i sig ökad efterfrågan på
kompetens: löneökningar, bonusar, arbetstid, förmåner och flytt av säte kan påverka.

Två premisser i tidigare underlag behöver korrigeras:

- RAMS har upphört; sista referensåret var 2021. BAS och Anställningar innehåller
  månatliga uppgifter. Jämförelsen mot en generell registerfördröjning på ett år är
  därför missvisande.
- Företagsspecifika arbetsgivaravgifter behöver inte komma från bokslut.
  Skatteverkets Hämta företagsinformation lämnar beslutade avgifter för tre månader.
  Det bevisar inte var UC/D&B hämtar uppgifterna; deras exakta källor är inte verifierade.

## Faktiskt inventerad datamängd

Hela officiella CSV-filen lästes: **1 451 534 rader**, ungefär 171 MiB.
Nio kolumner, 13 grupperingar och 36 statistiktermer över hela historiken.
Alla grupperingar är marginaltabeller i detta API: en gruppering och ett värde per rad.
Fullständiga värdelistor, termer, tidsintervall och uppdateringsdatum finns i
`docs/skatteverket-agi-inventory.json`. Räkningar beskriver observerad version,
inte garanterad täckning i varje månad eller för varje term.

| Gruppering | Observerade värden över historiken | Innebörd/begränsning |
| --- | ---: | --- |
| Total | 1 | Ingen gruppering; direkt nationell total |
| Län | 22 | 21 län och summeringsrest |
| Kommun | 291 | 290 kommuner och summeringsrest; namn utan kommunkod |
| Bransch | 166 | Tvåsiffrig SNI 2007/2025 och summeringsrest; 2026 har 80 branschvärden + rest |
| Antal anställda | 10 | 0, 1–4, 5–9, 10–19, 20–49, 50–249, 250–499, 500–999, >=1000; rest |
| Lönesumma | 10 | Företagens storleksklasser efter lönesumma; rest |
| Omsättning | 10 | Företagens storleksklasser efter omsättning; rest |
| Juridisk form gruppering | 12 | 11 former, bl.a. kommuner, regioner, statliga myndigheter; rest |
| Typ av person | 4 | Fysisk/juridisk/okänd; rest |
| Kön | 3 | Kvinna/man; rest. Bakgrund hos fysisk person, inte personalens könsfördelning |
| Åldersgrupp | 10 | Nio intervall; rest. Inte personalens åldersfördelning |
| Inkomstnivå | 14 | Historiskt varierande intervall för individers fastställda förvärvsinkomst; rest |
| Statlig inkomstskatt | 3 | Betalar/betalar inte/uppgift saknas |

**Geografisk definition:** individens folkbokföringsadress eller den juridiska
personens registrerade säte vid inkomstårets slut. Inte arbetsplats eller de
anställdas bostadskommun. En arbetsgivare med verksamhet i flera kommuner kan
belasta säteskommunen med hela redovisningen. En sätesflytt kan ge en förändring
utan att några jobb flyttat. Detta är en avgörande begränsning för regional analys.

Bransch avser registrerad SNI vid inkomstårets slut: SCB:s registrering används
i första hand, därefter Skatteverkets. Avsaknad hanteras i summeringsrest.
SNI 2025 används för inkomstår 2026, SNI 2007 för tidigare år. Ingen automatisk
årstakt över klassifikationsbytet utan verifierad jämförbarhet.

Storleksklass efter antal anställda omfattar personer som fått ersättning för
arbete i Sverige, även tillfälliga och mycket små ersättningar. Innevarande års
storlek baseras på senaste tolv månaderna; det är inte antalet aktiva jobb i månaden.
Omsättning och företagens lönesumma beräknas också för senaste tolv månaderna
under innevarande år. Gruppernas sammansättning kan ändras.

**Offentlig sektor är ingen SNI-bransch.** Juridiska former kan visas separat
för kommuner, regioner och statliga myndigheter, men det motsvarar inte en komplett
institutionell sektorklassificering. Vård/utbildning och offentliga bolag ska inte
automatiskt räknas som offentlig sektor.

## Mått

| Statistikterm | Användning |
| --- | --- |
| Bruttolön utom förmåner | Rekommenderad huvudserie för ersättningar utan förmåner |
| Lönesumma | Bruttolön + förmåner − avdrag för utgifter i arbetet, förenklat enligt portalen |
| Förmåner | Kompletterande komponent |
| Summa underlag arbetsgivaravgift | Avgiftsunderlag, inte synonymt med lönesumma i alla detaljer |
| Summa avgifter att betala | Skattemått med reduceringar/SLF; kompletterande serie |
| Summa avdragen skatt att betala | Innehåller även andra utbetalningar; svagare arbetsmarknadsproxy |
| antal | Unika arbetsgivare med icke-nollbelopp för termen; särskild regel för summeringsposter |

`antal` är **inte anställda**, även när grupperingen heter Antal anställda.
Årsantal kan inte byggas genom att summera månadsantal. Genomsnittligt belopp
per arbetsgivare är inte genomsnittlig lön per anställd. Belopp redovisas i kronor.
Testklienten behåller alla råa källvärden som text och gör ingen sekretessimputering.

## Tid, uppdatering och ofullständighet

API/CSV innehåller årsdata 2013–2026 och månadsrader 201301–202610.
Portalens definition säger samtidigt att månadsdata finns från 2019. Det är en
**källkonflikt**, inte verifierad AGI-jämförbarhet bakåt till 2013. Rekommenderad
dashboard-start är 2019 tills äldre historik/metodbrott har klarlagts.

Portalens översikt anger:

- Senaste två inkomståren uppdateras veckovis.
- Äldre år uppdateras månadsvis; uppdatering upphör när statistiken är äldre än sju år.
- Arbetsgivare deklarerar normalt den 12:e eller 26:e månaden efter utbetalningen.
- Föregående års deklarationer bör till största delen ha kommit in i början av februari.

Senaste källdatum för 2025/2026 var **2026-10-03**. Distributionsmetadata anger
2026-10-04T23:16:24.277Z. Dessa är olika datum: framställning respektive distribution.
Ingen fast publiceringsdag eller fullständighetsflagga har identifierats.

Observerade belopp för Lönesumma, inte syntetiska exempel:

| Månad | Riket, kr | Norrbotten, kr | Bedömning |
| --- | ---: | ---: | --- |
| 2026-08 | 215 335 366 344 | 4 130 523 781 | Kandidatmånad, inte garanterat slutlig |
| 2026-09 | 71 929 459 035 | 1 299 389 713 | Tydligt delrapporterad i denna version |
| 2026-10 | 141 797 881 | 4 388 954 | Pågående månad, får inte användas som trendsignal |

**Bedömd praktisk eftersläpning:** cirka en månad plus nästa veckouppdatering
efter den senare deklarationsfristen, alltså ungefär 4–5 veckor efter månadsslut
när flertalet deklarationer bör vara inne. Det är en slutsats utifrån tidsfristerna,
inte en utfästelse från Skatteverket. Sena deklarationer och rättelser kvarstår.
Vid körningen 9 oktober är augusti ett konservativt val; september bör vänta tills
senare frist och uppdatering passerat. Skriptets 33-dagarsregel är endast en
varningsheuristik och betecknar äldre månader som kandidat, aldrig som kompletta.

## API, metadata och filter

Ingen API-nyckel krävs för testade GET-anrop.

| Funktion | URL |
| --- | --- |
| JSON-data | https://skatteverket.entryscape.net/rowstore/dataset/b72fcfe9-cacf-4859-8f57-38357f6306b0 |
| Swagger | https://skatteverket.entryscape.net/rowstore/dataset/b72fcfe9-cacf-4859-8f57-38357f6306b0/swagger |
| Datasetmetadata (JSON-LD med Accept-header) | https://skatteverket.entryscape.net/store/26/resource/8 |
| API-distributionsmetadata | https://skatteverket.entryscape.net/store/26/resource/27 |
| CSV-distributionsmetadata | https://skatteverket.entryscape.net/store/26/resource/23 |
| Full CSV, Windows-1252 | https://skatteverket.entryscape.net/store/26/resource/22 |

Samtliga filterbara källkolumner: `period`, `uppdateringsdatum`, `gruppering`,
`statistikterm`, `antal`, `belopp`, `grupperingsvärde`, `inkomstar`, `ar_manad`.
Årsrader har tom `period`; kombinera därför `inkomstar` och `ar_manad=År`.
Månadsrader har `period=YYYYMM` och `ar_manad=Månad`. Värden är skiftlägeskänsliga
i testade uttag (t.ex. `NORRBOTTEN`). URL-koda svenska tecken med klientbibliotek.

Swagger anger `_limit` 1–500 (standard 100) och `_offset` i antal rader,
standard 0. Svar: `results`, `resultCount`, `offset`, `limit`, `next`, `queryTime`.
Läs alla sidor; jämför hämtat antal med `resultCount`; avvisa dubbletter.
Fel inkluderar 400, 404, 429, 500 och 503 (query timeout). Klienten gör begränsade
återförsök vid övergående fel och avvisar förändrade radantal/källversioner.

Filter kan kombineras mellan kolumner (AND). `|` väljer flera alternativ inom
en kolumn (OR). Skatteverkets API-guide dokumenterar `~` för delsträng och regex.
De reproducerbara proven använder exakta värden/alternativ och kontrollerar
att servern faktiskt har filtrerat. Inga okända filter som `kommun=25...` får
användas; de är inte dokumenterade och kan ge ett ofiltrerat uttag.

```python
from urllib.parse import urlencode
filters = dict(period='202608', ar_manad='Månad', gruppering='Län',
               grupperingsvärde='NORRBOTTEN', statistikterm='Lönesumma',
               _limit=500, _offset=0)
url = 'https://skatteverket.entryscape.net/rowstore/dataset/b72fcfe9-cacf-4859-8f57-38357f6306b0?' + urlencode(filters)
```

### Kombinerade dimensioner

Portalens definitioner tillåter två bakgrundsfakta samtidigt, **men kommun kan
inte kombineras med någon annan**. Län och bransch är därmed ett tänkbart portaluttag;
dess faktiska täckning/export är inte verifierad här.

Det här API:et/CSV-filen innehåller **inga korsade grupperingar**. Alla 1,45 miljoner
rader har bara en av de 13 grupperingarna ovan. `gruppering=Län|Bransch` returnerar
separata länsrader och nationella branschrader, inte bransch per län. Att samtidigt
skicka `grupperingsvärde=NORRBOTTEN` väljer bara länsraderna. Det går inte att
konstruera kommun × bransch × storlek genom att sammanfoga marginaltabellerna.

## Sekretess och rimlighetskontroll

Enskilda skattebetalare ska inte kunna identifieras. Skatteverket har infört
summeringsrader som omfattar både saknade uppgifter och sekretessdolda uppgifter.
I denna CSV finns inga icke-numeriska värden i `antal`/`belopp`; det betyder inte
att alla delgrupper är fullständigt redovisade. Saknade rader är inte noll.

Behåll `Summering av ej redovisade rader` som restkategori, utan att fördela den
på kommuner eller branscher. Hämta Riket direkt från Total. Summera aldrig
läns-, kommun-, bransch- och storleksrader tillsammans: de beskriver samma belopp
flera gånger. Balanskontroll gäller separat inom varje gruppering och term.
Rest i geografin kan innehålla okänd adress; nationell rest kan inte fördelas till län.

## Förslag till dashboard och modell

Om en kompletterande sätesbaserad vy väljs:

1. Bruttolön och lönesumma över tid för sätesbaserade kommuner/län och Riket.
2. Årstakt mot samma månad föregående år, endast för granskade kandidatmånader.
3. Rullande tremånadersbelopp och årstakt för att mildra bonus-/semestervariation.
4. Index: månadens belopp relativt årsmedel 2023 = 100, samma definition över tid.
5. Antal rapporterande arbetsgivare och restandel som kvalitetsinformation.
6. Nationella bransch-/storleksserier i en separat vy utan regionalt filter.

Datamodellens nyckel: dataset + tidsupplösning + period + statistikterm +
gruppering + grupperingsvärde + klassifikationsversion. Fält: råa antal/belopp,
normaliserade numeriska värden, källdatum, distributionsversion, hämtningstid,
restkategori, geografisk grund (`registered_seat_or_address`), kvalitetsstatus.
Geokod mappas från kommun-/länsnamn mot projektets geografilista, strikt med
fel vid okända namn. SNI-kod och version extraheras separat från etiketten.
Bransch-/storleksrader är nationella marginaler, inte regionala observationer.

Produktionsflöde efter separat beslut: egen staging och atomisk publicering,
förberäknade aggregat enligt AGENTS.md, ingen API-hämtning vid sidladdning.
Läs om historiska år när respektive års källdatum förändrats; bara senaste
månaden räcker inte för att fånga revisioner. Lagra snapshots för att kunna
mäta revisioner och tid till stabilitet. Ingen löpande körning är schemalagd nu.

## Testworkflows

- `90 · Test · Skatteverket AGI – klient`: syntetiska regressionsexempel för
  paginering, förändrat radantal, utebliven filtrering, dubbletter och tidsstatus.
- `90 · Test · Skatteverket AGI – datakälla`: laddar hela officiella CSV:n för
  inventering och provar JSON-uttag för Norrbotten, dess 14 kommuner, alla kommuner,
  SNI-branscher, storleksklasser, årsdata och Rikets senaste månader.

Båda kan köras manuellt och körs vid relevanta kodändringar enligt workflow-filerna.
Datakälleprovet sparar inventering, Swagger, uttag, filter, källmetadata och en
sammanfattning som Actions-artefakt i 30 dagar. Full CSV sparas inte i artefakten.
Inga secrets, databasanslutningar eller publiceringsbehörigheter behövs.
Grönt jobb betyder tekniskt prov godkänt; `ready_for_dashboard` är fortfarande false.

## Källor och kontrollspår

- [API-guide](https://www.skatteverket.se/omoss/varverksamhet/statistikportalen/hamtastatistikmedapi.4.262c54c219391f2e96320e6.html)
- [Statistikportalen](https://www.skatteverket.se/omoss/omskatteverket/statistik.4.6704c7931254eefbe718000121.html)
- [Användning av statistiken](https://www.skatteverket.se/omoss/digitalasamarbeten/omvaraoppnadata/hamtaskatteverketsstatistikmedapifransverigesdataportal.4.40cab8f8197edf03e64aee.html)
- Portalens Översikt och Definitioner i [AGD-applikationen](https://www6.skatteverket.se/sense/app/25ea5eaa-e2a2-41e1-aeed-29be5a28ddae/sheet/e4f9aa7e-de62-483a-801f-912761d52dbd/state/analysis), lästa i browser 2026-10-09.
- [SCB Anställningar](https://www.scb.se/hitta-statistik/statistik-efter-amne/arbetsmarknad/efterfragan-pa-arbetskraft/anstallningar/): juli 2026 publicerad 30 september; månatliga tabeller för lönesummor och anställningar.
- [SCB RAMS](https://www.scb.se/hitta-statistik/statistik-efter-amne/arbetsmarknad/utbud-av-arbetskraft/registerbaserad-arbetsmarknadsstatistik-rams/): upphört, hänvisar till BAS.
- [Företagsuppgifter](https://www.skatteverket.se/offentligaaktorer/informationsutbyte/forfraganforetagsuppgifter/foretagsuppgiftersomlamnasut.4.50a6b4831275a0376d380001839.html)

Öppna statistikuppgifter är fria att använda till valfritt ändamål enligt
Skatteverket. Namnge källan och förklara indikatorn. Ett mått på kompetensbrist,
rekryteringsbehov eller arbetade timmar kräver andra data; dessa kan inte härledas
entydigt ur lönesumman.
