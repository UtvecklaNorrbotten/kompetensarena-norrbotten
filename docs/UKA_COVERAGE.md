# UKÄ – verifierbar datatillgång och import till staging

Kontrollpunkt 2026-11-10. Fortsättning från den redan mergade PR #82,
på grenen `fix/uka-all-indicator-coverage`, PR #84.

Denna kontrollpunkt ersätter äldre nulägesbeskrivningar i UKA_RESTART.md,
UKA_CAMPAIGN.md och uka-import-investigation.md. Historiska bevis är bevarade.
Produktionsservern och aktiva publicerade batchar ändras inte i detta arbete.

## Resultat

Alla tio indikatorers **planerade** historiker finns nu i separat kontrollerad
filstaging: **1 639 839 observationer** inklusive källans egna överlappande totalrader.
Detta är observationsantal, inte antal unika studenter. Ingen produktionsimport är gjord.

| ID | Perioder | Observationer | Insamling |
|---|---:|---:|---|
| 13 | 20 | 73 268 | Ny CSV-staging |
| 31 | 20 | 73 716 | Ny CSV-staging |
| 33 | 10 | 1 151 372 | Tidigare paket, återverifierat offline |
| 97 | 20 | 71 394 | Ny CSV-staging |
| 99 | 20 | 19 595 | Tidigare paket, återverifierat offline |
| 108 | 10 | 119 840 | Ny CSV-staging |
| 136 | 5 | 9 899 | Ny CSV-staging |
| 77 | 10 | 14 812 | Ny CSV-staging |
| 134 | 10 | 56 525 | Ny CSV-staging |
| 135 | 10 | 49 418 | Ny CSV-staging |

De åtta nya indikatorerna omfattar 105 perioder, 468 872 observationer,
315 lyckade CSV-uttag och 1 125 JSON-rotsvar för hela köns-/åldersplanen.
Alla 4 154 observationer i de åtta äldre fullständiga JSON-referenserna matchar
färsk CSV exakt. Ytterligare 38 riktade detaljkontroller passerar.

138 lokala UKÄ-tester passerar. Nya testfall omfattar verklig offlinefixtur,
rollback vid avbruten skrivning, oförändrad återstart, manifest-/hash-/värdespärrar,
dubbletter och skilda statusar för tekniskt tomsvar och oklar tom selektion.
Workflowets PR-test är också verifierat i GitHub; slutlig körningsreferens finns i leveranskvittot.

## Läs rapporterna i denna ordning

1. Denna rapport för resultat, begränsningar och nästa åtgärd.
2. `uka-coverage-summary-2026-11-10.json` för antal, perioder, kontroller och kontrollsummor.
3. `uka-source-options-2026-11-10.json` för **samtliga exakta erbjudna värden**,
   koder, etiketter och hierarkiska föräldrarelationer i alla tio indikatorer.
4. Datapaketets `coverage-report.json` för periodvis faktisk förekomst, frånvarourval,
   exportfilter, käll-URL:er och JSON-hashar. SQLite innehåller varje faktisk observationsnyckel.

Metadataalternativ får inte tolkas som en fullständig kartesisk produkt av data.
Källans frånvaro skapar aldrig nollobservationer.

## Dimensioner och avgränsningar

Alla tio erbjuder Kvinnor, Män och Total. Alla erbjudna lärosäten, även historiska,
begärs uttryckligen. Riket är ett eget källvärde. De tre indikatorerna 99, 136 och 77
har endast teknisk ålderstotal. Övriga har -24, 25-34, 35- och Total.
En teknisk total innebär inte att källan erbjuder åldersuppdelning.

| ID | Statistik | Valda perioder | Extra dimensioner | Lärosätesval inkl. Riket |
|---|---|---|---|---:|
| 13 | Förstahandssökande till yrkesexamensprogram | VT2017–HT2026, 20 terminer | Program | 82 |
| 31 | Nybörjare på yrkesexamensprogram | HT2016–VT2026, 20 terminer | Källkolumnen Studieform innehåller program/examina | 116 |
| 33 | Helårsstudenter | 2016/17–2025/26 | Studieform och Ämnesområde → Ämnesdelområde → Ämnesgrupp | 78 |
| 97 | Antagna till yrkesexamensprogram | VT2017–HT2026, 20 terminer | Program | 82 |
| 99 | Söktryck till yrkesexamensprogram | VT2017–HT2026, 20 terminer | Program | 81 |
| 108 | Examinerade | 2015/16–2024/25 | Examenskategori → Examen → Inriktning | 120 |
| 136 | Etablering på arbetsmarknaden | 2020–2024, fem år som erbjuds | Examen | 52 |
| 77 | Kvarvaro termin 3 för högskolenybörjare | 2015/16–2024/25 | Studieform × Utbildningsnivå | 86 |
| 134 | Kvarvaro termin 3 på program | 2014/15–2023/24 | Program | 66 |
| 135 | Examensfrekvens på program | 2012/13–2021/22 | Program | 64 |

Varje vald period hämtas separat med hela dess erbjudna filterutbud.
JSON-kategorilistor kontrolleras per period, kön och ålder, inte bara senaste årets lista.
Fullständiga observerade dimensionsvägar och lärosäteskoder finns i den maskinläsbara rapporten.
Rapporten skiljer mellan erbjudna alternativ och faktiskt observerade värden.

## Verifierade problem och källans begränsningar

- **33:** hela ämnesvägen bevaras. Koden för Övrigt återanvänds under olika föräldrar;
  endast kod eller etikett är därför otillräcklig identitet. Bred CSV är huvudkälla;
  den tidigare kontextkonflikten i JSON:s alternativa navigeringsvägar kvarstår som
  regressionsevidens. Det innebär inte att CSV eller alla JSON-vägar är trasiga.
- **108:** Inriktning är en faktisk tredje nivå, inte ett okänt tillägg att ignorera.
  Den erbjuds bara för examina som har inriktningar. Äldre fullständiga JSON-grafen
  återbyggs från hashkontrollerade råsvar och jämförs med färsk CSV, inklusive denna nivå.
  Direkta köns-/åldersprov omfattar Yrkesexamina → Civilingenjörsexamina → Inriktning.
- **135:** nybörjarläsåret måste följas i programmets nominella längd plus tre år.
  UKÄ förklarar att de senaste årens redovisning därför bara omfattar kortare program.
  Agronomexamen är en positiv historisk observation men annonseras inte i senaste
  nationella programlistan. Historiska program får inte filtreras med senaste årets lista.
- **13:** färska metadata, bred CSV och alla köns-/ålderskontroller fungerar.
  Tidigare HTTP 503 är historiskt tekniskt fel, inget belägg för saknade variabler.
- **31:** UKÄ dokumenterar ändrad kodning av ULV/VAL från VT2021 och en aviserad
  historisk justering. Det är en källfråga som kräver revisionskontroll.
  Källans kolumnnamn Studieform behålls även när värdena är examensprogram.
- **13 och 97:** antagningsstatistiken omfattar källans samordnade antagningssystem
  och avgränsas till fullständiga personnummer. Utbildning utanför systemen kan saknas.
  Terminer och program kan inte fritt summeras; källans totaler är nettoräknade.
- **108:** nettoräkning görs på varje nivå; examenskategoriernas värden behöver
  därför inte summera till totalen. Ingen sådan kontrollsumma konstrueras.
- **77:** inresande studenter är exkluderade; kvarvaro gäller samma lärosäte.
- **134:** inkluderar inresande; vissa korta program och kompletterande lärarutbildningar
  är exkluderade. Riket och lärosätesuppgifter har olika definition av lärosätesbyte.
- **136:** uppföljningsår, inte examensår; uppföljning görs 1–1,5 år efter examen.
  Studerande och utflyttade exkluderas. Bara en examen per person och läsår räknas,
  med yrkesexamen prioriterad vid dubbelexamen. Åldersuppdelning erbjuds inte.
- **99:** källans decimaltal bevaras; söktrycket kan understiga 1.
  Totaler får inte konstrueras som medelvärden av programvärden.

**Sekretess:** inga generella tröskelregler har verifierats för alla dessa tio indikatorer.
UKÄ:s regel om små antal i avsnittet om antagna till *generella* program tillämpas
inte på yrkesexamensindikator 97. Frånvaro, null och markörer är inte liktydiga med noll.
En kvarstående osäkerhet är varför en viss oannonserad detaljcell inte redovisas.

Officiella definitioner, kontrollerade 2026-11-10:

- https://www.uka.se/statistik-och-analys/hogskolan-i-siffror/beskrivningar-av-statistiken/utbildning-pa-grundniva-och-avancerad-niva
- https://www.uka.se/statistik-och-analys/hogskolan-i-siffror/beskrivningar-av-statistiken/etablering-pa-arbetsmarknaden
- Exportfilter: https://statistik-www.uka.se/export/filters/
- JSON-källa: https://statistik-api.uka.se/api/totals/

## Hur täckning och frånvaro kontrolleras

De åtta nya insamlarna kräver för varje period:

1. Lyckad bred CSV med alla uttryckligen begärda lärosäten, kön, åldrar och gruppval.
2. Exakt samma observationsnycklar och värden i unionen av två disjunkta lärosätesuttag.
3. Överensstämmelse med varje nationellt JSON-rotsvar för kön × ålder, inklusive
   källans total, lärosätestotaler och nationella första dimensionsnivåer.
4. Giltiga hierarkiska vägar, rätt period och filter, samt inga dubbla logiska nycklar.
5. En transaktion för periodens rader, rapport, kontrollsumma och färdigmarkering.

Dessutom återbyggs de åtta fullständiga historiska JSON-referensgraferna med noll
nätbudget. De jämförs mot färsk CSV för senaste perioden/Total kön/Total ålder.
Det är också en avgränsad revisionskontroll; datum eller metadatahash är inte en
oföränderlig källversion. Köns-/åldersuppdelade detaljprov görs separat för äldsta
respektive senaste perioden, med annonserade länkar och direkt lärosäteskontroll.

HST och 99 använder sina tidigare starkare CSV-partitionskontroller även i en andra
layout (studieform respektive program), JSON-rotsvar och avslutande stabilitetsprov.
Deras tidigare kampanjer ersätts inte. HST:s 1 446 och 99:s 531 filhashar samt
samtliga perioders stagingkontrollsummor har återverifierats offline.

| Klass | Bevis och konsekvens |
|---|---|
| Verifierad data | Observation i kontrollerad CSV; JSON-likvärdighetens exakta omfattning redovisas separat. |
| Verifierat saknad kombination | Exakt urval saknas i lyckat bredare uttag och oberoende positiv JSON-lista. Ingen nolla skapas och orsaken gissas inte. |
| Sekretess/undertryckt eller ej redovisat värde | Explicit null/markör bevaras. Orsaken klassas inte som sekretess utan relevant dokumentation. |
| Tekniskt fel | HTTP-/transportfel, nollbyte eller felaktig CSV. Staging färdigmarkeras inte. |
| Oklart | Rubrikfil utan positiv referens, värdekonflikt eller frånvarande detaljcell som inte har tillräckligt stöd. |

Frånvarolistorna gäller angivna perioder, kön och åldrar. De är inte ett påstående
att ett lärosäte saknar all verksamhet, eller att en osynlig detaljcell har värdet noll.
Faktiska detaljer kan slås upp i SQLite; oannonserade detaljer med otillräckligt
underlag redovisas uttryckligen som oklara, inte som importfel eller säkra strukturella nollor.

## Problem i vår kod jämfört med begränsningar i källan

Den tidigare produktionsvägens rekursiva uppdelning av smala CSV-urval kan stoppa
på ett rubrikuttag som ännu saknar positiv frånvaroverifiering. En generell
nollbytes-/HTTP-tolerans vore inte en säker lösning. Den nya insamlaren utgår
från breda uttag och färdigmarkerar bara kontrollerade perioder.

Den tidigare publiceringsvägen i `R/etl/uka_sync.R` och `uka-etl.server.ts`
har inte serverkontrollerat källtäckningsmanifest eller stabil återstartnyckel.
R-klientens abort vid misslyckande förlorar möjligheten till fortsatt uppladdning;
aggregatomräkning sker efter finaliseringsanropet. Dessa är våra kvarvarande
produktionsproblem, inte UKÄ:s databegränsningar. Den nya filstagingen används
inte automatiskt av den äldre produktionsvägen.

Under detta arbete rättades även en omkastad mappning av indikator 77:s två
exportgrupper, med ett uttryckligt regressionstest. Det felaktiga provet stoppades
innan någon period skrevs; den redan hämtade CSV-filen återanvändes efter rättningen.

## Kod, återstart och nästa steg

- `scripts/uka_verified_collection.py`: de åtta nya indikatorerna, standardbudget noll.
- `scripts/uka_detail_controls.py`: riktade JSON-prov mot sparade CSV-detaljer.
- `scripts/uka_coverage_report.py`: spårbar rapport och offlineåterbyggnad av äldre referenser.
- `.github/workflows/uka-verified-coverage.yml`: separata tester och manuell insamling;
  välj en indikator och pilot/all, ange tidigare körning för återstart.
- `scripts/uka_campaign.py` och `uka_json_queue.py`: bevarad återstartbar JSON-reserv
  när en CSV-väg blockeras. En ofullständig graf får aldrig ersätta ett komplett CSV-paket.

En ny kolumn, ogiltig hierarki, felaktigt värde, tekniskt tomsvar eller ändrat manifest
stoppar skrivningen. Budgetslut pausar och behåller källsvaren. Nya kampanjer är
separerade från 2026-11-06-kampanjens oförändrade manifest.

**Motargument mot ett för starkt täckningspåstående:** två CSV-layoutar kan dela
samma källfel. JSON-rotsvar och riktade detaljprov reducerar den risken men bevisar
inte varje historisk detaljcell oberoende. Därför är fullständig oberoende
bladverifiering och oföränderlig källversion inte markerade som klara.

**Före produktionsimport återstår:** anslut den kontrollerade filstagingen till en
serverkontrollerad uppladdnings-/publiceringsväg med stabil importnyckel, manifest,
progress/status och idempotenta chunkar. Testa att ofullständiga manifest stoppas,
att tillfälliga fel kan återupptas och att föregående aktiva batch bevaras tills
aggregat och återläsning är godkända. Fastställ och genomför revisionskontroll för
hela det frysta publiceringsunderlaget. Ingen ny klientflagga får kringgå dessa krav.

Det separata pågående arbetet med HST:s publiceringsväg ska samordnas innan samma
serverfunktioner eller migrationer ändras. Detta arbete har inte ändrat dessa filer.
