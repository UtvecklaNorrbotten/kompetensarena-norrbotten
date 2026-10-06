# Utbildning med UKÄ-data

Utbildning är en sammanhängande sida med fyra avsnitt: Sökande och antagna,
Studenter, Examina och Arbetsmarknad efter examen. Vänstermenyn använder ankarlänkar
på sidan och markerar aktuellt avsnitt under scrollning. Direkta ämneslänkar visar
hela sidan och scrollar till respektive avsnitt; gamla platshållarlänkar fungerar fortfarande.

## Sidfilter och figurer

- Filterkolumnen ligger intill områdesmenyn och är fast vid scrollning på stora skärmar.
  På mobilen ligger den före innehållet. Lärosätet gäller samtliga figurer; Luleå tekniska
  universitet är förval, med Riket som reserv om LTU saknas.
- Kön och tidsomfång är gemensamma. Fler filter visar uppdelningarna i aktuellt
  lärosätes data. När lärosäte byts återställs dimensionsurvalen. Kön/tidsomfång behålls.
- Dimensionsfilter gäller endast indikatorer med motsvarande dimension; figuren
  förklarar när ett urval saknar motsvarighet. Filtreringen innehåller ingen geografisk
  mappning av lärosäten till kommuner eller län.
- Översikt visar en tidsserie. Fördjupning visar senaste tillgängliga perioden i urvalet,
  uppdelad på källans grupper och, när Samtliga har valts och data finns, kvinnor/män.
  De tolv högsta värdena visas först; användaren kan visa alla grupper och hela tabellen.
- Begrepp med streckad understrykning öppnar en förklarande popover. Ett frågetecken
  visas vid hovring och tangentbordsfokus; funktionerna fungerar också på pekskärm.

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

- `node --import tsx tests/uka-view.test.ts`: syntetiska exempel för totaler,
  hierarkier, överlappande grupper, kön, saknade värden och terminsgränser.
- `npx tsc --noEmit`, ESLint på ändrade filer samt `npm run build`.
- Totaler, perioder och fördjupningar kontrollerade mot publicerade LTU-aggregat
  för alla sju indikatorer. Begrepp kontrollerade mot UKÄ:s statistikbeskrivningar.

Källor för begrepp: UKÄ:s [statistikinformation](https://www.uka.se/statistik-och-analys/om-var-statistik/information-om-statistiken),
[statistik om utbildning](https://www.uka.se/statistik-och-analys/hogskolan-i-siffror/utbildning-pa-grundniva-och-avancerad-niva)
och [etableringsstatistik](https://www.uka.se/om-oss/aktuellt/nyheter/nyhetsartiklar/2026-05-27-nagot-lagre-etablering-bland-nyexaminerade).
