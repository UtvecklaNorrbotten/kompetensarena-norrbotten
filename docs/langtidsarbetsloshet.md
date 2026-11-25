# Långtidsarbetslöshet

Sida: `/omraden/arbetsmarknad/langtidsarbetsloshet?geo=25`.

## Källor och beräkningar

Befintliga AF-importer används, utan en ny parallell hämtning:

- `af-tid-utan-arbete`: månadsserier från januari 2006. Kommuner och härledda län ur `web-inskrivna-arbetslosa-tid-utan-arbete-lan-kom`, separat rikstotal ur `web-tid-riket`.
- `af-arbetssokande`: nämnare, INSAL, samma geografi, månad och grupp. Totalen och könstotalerna härleds endast ur åldersuppdelningen. Ålder, utbildningsnivå och födelseland är alternativa uppdelningar och summeras aldrig med varandra.

Källsida: https://arbetsformedlingen.se/statistik/sok-statistik/tidigare-statistik-tidsserier

Originalfilerna för oktober 2026 har kontrollerats direkt 2026-11-25. Bladet Info definierar sammanhängande tid utan arbete bland öppet arbetslösa och arbetslösa i program. Gränserna är **mer än** 6, 12 och 24 månader. Riket använder UA06/UA12/UA24 och län/kommun KUA06/KUA12/KUA24. De är överlappande mått.

Staplarna har fyra ömsesidigt uteslutande intervall:

| Intervall | Beräkning |
| --- | --- |
| Högst 6 månader | INSAL − UA06 |
| Mer än 6, högst 12 månader | UA06 − UA12 |
| Mer än 12, högst 24 månader | UA12 − UA24 |
| Mer än 24 månader | UA24 |

Andel = 100 × täljare / INSAL. Noll i nämnaren ger ingen andel. Ingen avrundning sker före beräkningen. Negativa eller icke-monotona intervall visas inte. Uppdelningarna kan inte korsfiltreras eftersom tid-filen bara innehåller marginalfördelningar.

### Sekretess och jämförbarhet

ETL behåller `<5` som en undre gräns med `value_is_lower_bound`. Aggregatet behåller flaggan separat för varje tröskel. UI visar gränsen med förklaring, utan exakt diagramvärde eller exakt andel. Full stapling kräver exakta värden för alla intervall. Tomma diagram förklaras uttryckligen. Tabellalternativ visar även sekretessstatus.

För oktober 2026 har Arjeplog `<5` i måttet mer än 24 månader. Norrbottens total för detta mått blir därför en undre gräns. Totalen mer än 12 månader är däremot exakt. Uppdelade länsvärden har oftare sekretessflaggor och får aldrig tyst ersättas med noll.

Åldersomfattningen ändras: 16–64 år 2006–2022, 16–65 år 2023–2025, 16–66 år från 2026. Serien är inte säsongsrensad. Sidan markerar brotten och undviker att kalla hela historiken oförändrat jämförbar.

## Läsning och uppdatering

`agg_af_duration` förberäknar samtliga importerade geografier, perioder och fyra gruppindelningar. Sidan läser bara detta aggregat via `af-duration.functions.ts`, aldrig råobservationer. Historiken läses i sidor; jämförelser hämtas för en månad i taget. Geografin sparas i URL, Norrbotten är förval. Alla län kan jämföras; kommunjämförelsen följer valt län.

`agg_refresh_af_duration()` körs timvis. Markören innehåller **både aktiv batch och metadata.updated_at** för båda indikatorerna. Det behövs eftersom `replace_period` uppdaterar observationer inom samma batch. Den äldre AF-kontrollen reagerar bara på batch-ID och kan därför lämna `agg_af_totals` på en äldre period. Den nya sidan använder det separata, sekretessbevarande aggregatet; andra sidor ändras inte.

Migration: `drizzle/migrations/0059_af_duration.sql`. Körs i projektets databas, följt av en första `agg_refresh_af_duration()`. Omräkningen är atomisk och låst mot samtidiga körningar. Endast service_role kan anropa funktionen; anonyma och inloggade besökare får bara läsa aggregattabellen.

## Verifiering

- TypeScript-kontroll och produktionsbygge.
- ESLint för nya komponenter och beräknings-/serverfunktioner.
- `node --experimental-strip-types tests/af-duration.test.ts`: differenser, andelar, noll, saknade tal, sekretess och inkonsistenta intervall; syntetiska exempel.
- SQL-funktionen testad i lokal PostgreSQL (PGlite) med syntetiska observationer: gruppnämnare, UA/KUA, flaggor, oförändrad markör, revision inom samma batch och anonym läsbehörighet utan skrivrätt eller omräkningsrätt.
- Originalfilens rikstal för oktober 2026: INSAL 338 643, UA06 205 691, UA12 146 076, UA24 82 940. Dessa används endast som verifieringsvärden, aldrig som frontenddata.


### Produktionskontroll 2026-11-25

Migrationen är applicerad. Första omräkningen publicerade 972 853 aggregatrader, januari 2006–oktober 2026, med 312 geografier. Alla grupper har matchande nämnare. Omräkningen tog cirka 215 sekunder och behöver därför en explicit sessionsgräns på tio minuter i cron-kommandot; funktionens SET räcker inte för att ändra en redan startad statement-timer. Engångsjobbet avregistrerades efter lyckad körning. En omedelbar kontroll gav `no_change`.

Kontroll mot originalfilerna för oktober 2026:

| Område | Inskrivna arbetslösa | >6 månader | >12 månader | >24 månader |
| --- | ---: | ---: | ---: | ---: |
| Riket | 338 643 | 205 691 | 146 076 | 82 940 |
| Norrbotten | 4 222 | 2 267 | 1 515 | minst 784 |
| Arjeplog | 54 | 26 | 12 | sekretessmarkerat |

Originalfilerna har SHA-256 `7ad18b1d315821e94345f115e4ff999fc67eb6061bbda4a133c1dd5ca4b89f07` (riket) och `a6756c5635214fbf342eab9074deff20dbefe1705d16c9baa68223e9d76ded37` (län/kommun).

Anonym HTTP-läsning gav 200 med 250 månader för Norrbotten. Besökare har uttryckligen endast SELECT; databasens standardbehörigheter för nya tabeller återkallas innan läsning beviljas. Omräkningsfunktionen kan inte anropas anonymt. Gränssnittets förhandsvisning har kontrollerats med verkliga data: antal/andel, kommunjämförelse, utbildningsnivå, byte till Riket samt tabellen för hela historiken.
