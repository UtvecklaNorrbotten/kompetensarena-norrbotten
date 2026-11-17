# Årsredovisningar: kompletteringar och reservationer

## Avgränsning och kontrollpunkt

Senaste tillgängliga digitala årsredovisning per företag i aktuellt Norrbottensurval,
inte historisk hämtning av alla år eller hela Sveriges årsredovisningar.
Startkontroll 2026-11-17: 47 889 företag, 10 607 bulkkandidater, 10 415 verifierade
senaste bokslut, 192 i karantän, 0 väntande i urvalet, 37 282 utan bulkkandidat.
Urvalet har ändrats efter nya AFR-publiceringar; jämför inte blint med äldre antal.

Migration `0054_company_account_supplements.sql` är manuellt applicerad, inte
journalförd för automatisk återapplicering. RLS/adminläsning/service_role-skrivning.
Ett transaktionstest verifierade idempotens och behörigheter och rullades tillbaka.

## Reservationer utan att skriva över verifierade data

`company_account_supplements` lagrar versionsbundna källor och valfria tolkade
värden separat från `company_accounts_latest`. Status:

- `with_reservation`: tolkade värden, period/valuta, proveniens, dokument- och
  paketkontrollsummor samt exakt orsak till reservationen.
- `source_only`: paketet är sparat men värden kan ännu inte användas säkert.

En flaggad post är **inte** ett verifierat bokslut och ingår inte i verifierade
summeringar eller arbetsställefördelningar. Inga tidigare bokslut, senaste-pekare
eller fördelningar skrivs över. Nuvarande karantänstatus behålls i den strikta importen.
En framtida företagssida måste explicit hämta reservationer och visa flaggorna;
den sidan byggs inte i detta steg. Gamla versioner behålls; en konsument måste
matcha aktuell kandidatkontrollsumma så att en äldre reservation inte visas som nyast.

Den strikta parsern är oförändrat strikt. Separat opt-in accepterar den observerade
K2-entrypointen `risbs/2017-09-30` tillsammans med endast kända officiella
2017-K2-/revisions-entrypoints på `xbrl.taxonomier.se`. Okänd värd/version,
koncernbegrepp och dimensionerade dokument avvisas. Samma kontroller av
organisationsnummer, period, enheter, belopp och avrundning kvarstår. Ingen
DTD-/entitetstolkning aktiveras. Saknad `FinansiellRapportList` sparas som
`legacy_k2_missing_scope_declaration`, med `scope_basis=inferred_legacy_k2_with_reservation`.

## API-komplettering och återstart

`10 · Data · Bolagsverket – kompletteringar och reservationer` behandlar först
sparade karantänpaket, sedan högst 1 000 AB per körning som saknar bulkkandidat.
Bank- och försäkrings-AB ingår. API-takten är högst 50 anrop/minut. Körningen
fortsätter var fjärde timme utan överlapp inom kompletteringsflödet.

Varje företag kvitteras privat i `company_account_api_checks`, inklusive resultat
utan dokument. Lyckade/entydigt avslutade kontroller kontrolleras igen efter 30 dagar,
anropsfel efter en dag. Avbrott behåller kvitterade företag och sparade paket.
API-dokument sparas privat med ursprunglig nedladdningshash och dokument-ID/
registreringsmetadata, även om bara PDF eller otolkningsbar XHTML finns.
API-källor är supplement och blir inte automatiskt verifierade senaste bokslut.

Tvetydig dokumentordning flaggas och väljs inte godtyckligt. Metadata för sådana
fall behöver fortsatt särskild granskning; ingen osäker period väljs för att höja täckningen.

Endast summeringar loggas. Inga företagsidentifierare, dokument, kontakter,
signerade URL:er eller API-hemligheter läggs i GitHub-artifacts.

## Återuppta

1. Kontrollera aktuell Actions-körning för kompletteringsworkflowet.
2. Läs antal per `origin`, `quality_status`, `reason` i supplementtabellen och
   antal per `outcome` i API-kontrollerna, avgränsat till aktuellt urval.
3. Räkna AB utan bulkkandidat och utan giltig API-kontroll. Nästa schemakörning
   börjar automatiskt med återstående företag, inget fullständigt omtag behövs.
4. Rapportera verifierade bokslut, reservationer och källdokument utan tolkning
   separat. En tom API-lista bevisar inte att företaget saknar en årsredovisning;
   det kan saknas en digital rapport i just denna tjänst.

Produktionsutfall kompletteras efter faktisk körning. Ingen full täckning är utlovad.
