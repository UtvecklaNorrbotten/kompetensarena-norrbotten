# Utbildning med UKÄ-data

Utbildning är en sammanhängande sida med två grupper: Högskolan – studier,
examina och arbetsmarknad samt Yrkesexamensprogram i högskolan. Den senare
samlar förstahandssökande, antagna, söktryck och nybörjare. Yrkesexamensprogram
är högskoleutbildningar och ska inte märkas som yrkeshögskola (YH).
Vänstermenyn använder ankarlänkar och markerar aktuell grupp under scrollning.
Tidigare ämneslänkar öppnar motsvarande grupp på den kompletta sidan.

## Sidfilter och figurer

- Filterkolumnen ligger intill områdesmenyn och är fast vid scrollning på stora skärmar.
  På mobilen ligger den före innehållet. Lärosätet gäller samtliga figurer; Luleå tekniska
  universitet är förval, med Riket som reserv om LTU saknas.
- Könsfiltret är borttaget. Kvinnor och män visas samtidigt i båda diagramlägena. Tidsomfångsfiltret är borttaget; alla lagrade perioder visas. Fler filter visar uppdelningarna i aktuellt
  lärosätes data. När lärosäte byts återställs dimensionsurvalen.
- Dimensionsfilter gäller endast indikatorer med motsvarande dimension; figuren
  förklarar när ett urval saknar motsvarighet. Filtreringen innehåller ingen geografisk
  mappning av lärosäten till kommuner eller län.
- Översikt visar en tidsserie. Fördjupning visar senaste tillgängliga perioden i urvalet,
  uppdelad på källans grupper med separata staplar för kvinnor/män när data finns.
  De tolv högsta värdena visas först; användaren kan visa alla grupper och hela tabellen.
- Begrepp med streckad understrykning öppnar en förklarande popover. Ett frågetecken
  visas vid hovring och tangentbordsfokus; funktionerna fungerar också på pekskärm.

## Nedladdning och läsbarhet

Varje figur har en Spara figur-knapp uppe till höger. PNG-exporten använder
aktuellt diagramläge och visar titel, urval, enhet, källa och hämtningsdatum.
Fördjupningens begränsning till tolv grupper följer med i bilden när den är aktiv.
Kvinnor/män markeras även i den exporterade bildens förklaring.

CSV-knappen ligger till höger om Visa värden som tabell. Exporten använder
exakt tabellens rader, inte diagrammets begränsning till tolv grupper.
CSV har UTF-8 BOM, semikolon, decimalcomma och citattecken; null blir tomt fält.
Mått, lärosäte, period, grupp, kön, värde, enhet och källa följer med.

Brödtexten är 16 px och normal textvikt, även begreppsförklaringar.
Långa kategorietiketter radbryts utan avkortning och radhöjden följer texten.
På smala skärmar kan själva diagramytan skrollas horisontellt för att behålla
läsbara etiketter. Axeltexter har större marginaler och större text.

## Dataläsning och skydd mot dubbelräkning

`getUkaUniversities` och `getUkaEducation` i `src/lib/aggregates.functions.ts` läser
endast publikt tillgängliga `agg_uka_university` via publishable key och RLS.
Råobservationer läses aldrig i sidflödet. Indikatorerna är uttryckligen avgränsade
till UKÄ 13, 31, 33, 97, 99, 108 och 136. PostgREST-svaren pagineras med 1 000
rader; fel och storleksgränser stoppar läsningen i stället för att visa ofullständiga data.
Inga nya migrationer behövs; befintligt UKÄ-aggregat används.

`uka-view.ts` väljer källans minsta lagrade dimensionsprojektion som innehåller
aktuella filter. Kön, totaler, olika hierarkinivåer, andelar och söktryck summeras
aldrig i klienten. Om ett urval ger flera överlappande grupper i översikten visas
ett meddelande som ber användaren precisera urvalet eller öppna fördjupningen.
Saknade värden förblir saknade. Fem år av terminsdata betyder tio terminer;
läsårs- och kalenderårsdata använder fem perioder.

## Kontroller

- `node --import tsx tests/education-export.test.ts`: syntetiska exempel för
  CSV-rader, decimaler, citering, svenska tecken, saknade värden och radbrytning.
- PNG-exportens webbläsarflöde och den visuella layouten behöver kontrolleras
  i Lovables förhandsvisning; en fungerande lokal webbläsare saknas i exekveringsmiljön.

- `node --import tsx tests/uka-view.test.ts`: syntetiska exempel för totaler,
  hierarkier, överlappande grupper, kön, saknade värden och terminsgränser.
- `npx tsc --noEmit`, ESLint på ändrade filer samt `npm run build`.
- Totaler, perioder och fördjupningar kontrollerade mot publicerade LTU-aggregat
  för alla sju indikatorer. Begrepp kontrollerade mot UKÄ:s statistikbeskrivningar.

Källor för begrepp: UKÄ:s [statistikinformation](https://www.uka.se/statistik-och-analys/om-var-statistik/information-om-statistiken),
[statistik om utbildning](https://www.uka.se/statistik-och-analys/hogskolan-i-siffror/utbildning-pa-grundniva-och-avancerad-niva)
och [etableringsstatistik](https://www.uka.se/om-oss/aktuellt/nyheter/nyhetsartiklar/2026-05-27-nagot-lagre-etablering-bland-nyexaminerade).

## Kön i figurerna

Översikten visar Kvinnor (grön linje) och Män (grå streckad linje) med legend.
Fördjupningen visar parallella staplar med samma färger. Totalvärdet visas som
Samtliga i nyckeltalet; tabell och CSV behåller kvinnor, män och källans total.
Om könsuppdelning saknas visas Samtliga med förklarande text. Saknade könsvärden
förblir luckor. Andelar och söktryck för könen beräknas aldrig från totalen.

## Total och söktryck

Totalen visas som tredje serie (gul) vid sidan av kvinnor (grön) och män (grå).
Alla serier använder samma kronologiska terminssortering; tidigare totalserie
följde CSV/databasens textsortering med alla HT före alla VT.

Söktryck visas med exakt en decimal. UKÄ:s decimaler bevaras i importen genom
`uka_values.R`; tidigare omtolkades redan numeriska värden med svensk locale,
vilket tappade decimaldelen. Importändringar på main startar UKÄ-workflowet
för att ersätta felaktiga snapshotar; parserns R-tester körs före publicering.


Fördjupningens periodval: terminsdata visas för ett kalenderår med VT och HT som
separata stapelgrupper per program och kvinnor/män/total inom varje termin.
Förvalet är senaste året med båda terminerna; senare år kan väljas även med en
enda publicerad termin. Val av enbart HT eller VT finns. Terminer summeras aldrig,
och en saknad terminsrad skapas inte som noll. Års-/läsårsdata behåller källans
periodindelning. Tabell och CSV följer periodvalet, PNG anger valda perioder.
Grupper sorteras alfabetiskt så samma program och dess terminer ligger intill
varandra; fler än 12 program kan visas med Visa alla.


Översiktens terminsserier visas som VT till vänster och HT till höger (staplade
på mobil) med samma årtal och gemensam y-skala. Hover-tabellen visar båda
terminerna för samma år. Klickbara legendknappar styr serierna i båda panelerna;
saknade termin-/årsvärden förblir null. Årsdata visas i en enda panel.
I programfördjupningen finns Jämför program över tid med val av 1–3 program.
Program skiljs med färg och kön med linjetyp. Kvinnor, män och källans total
behålls; programmens värden summeras aldrig. Tabell och CSV följer valda program
över alla publicerade perioder. PNG-exporten omfattar båda terminsdiagrammen
med rubriker, färger och linjetyper beskrivna i bildtexten.
