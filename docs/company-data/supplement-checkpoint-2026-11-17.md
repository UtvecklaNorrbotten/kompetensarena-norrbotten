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
K3-/koncern-entrypoints och dimensionerade dokument avvisas. Samma kontroller av
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

Produktionskörning: [44139154667](https://github.com/UtvecklaNorrbotten/kompetensarena-norrbotten/actions/runs/44139154667).
Kod: PR #100, merge `b3f1b0d2ede79045334ef67498eb11017d50daac`.
CI-körning 44139051258 passerade; 52 Python- och 6 Node-tester.
De fem tidigare redovisade verkliga K2-källpaketen kontrollerades med oförändrad
pakethash och kunde tolkas med reservation.

Aktuellt AB-urval vid start: 16 927 (inklusive bank-/försäkrings-AB), varav
10 415 strikt importerade, 192 i karantän och 6 320 utan bulkkandidat. API-kontrollen
är en faktisk kontroll av dessa 6 320, inte en extrapolering av ett stickprov.
Den är inte färdig bara för att ett första deljobb är klart.

Den strikta bulkimporten fick åter SQLSTATE 21000 vid första scope-anropet efter
publicering (körning 44139154768). Direkt anrop av `company_data_scope(null,1000)`
lyckades och den misslyckade körningen återstartades därefter. Grundorsaken är
fortfarande inte fastställd; detta ska inte beskrivas som en permanent rättning.
Kompletteringsflödet har separat per-företag-kvittering och ändrar inte verifierade
bokslut. Slutliga antal och återstående kö kompletteras nedan efter databaskontroll.
Ingen full täckning är utlovad.

## Verifierat produktionsutfall 2026-11-17 cirka 18:49 svensk tid

- Alla **192** ursprungliga karantänpaket har behandlats och lagrats i supplementtabellen.
- **164** har tolkade värden med reservation; **28** har enbart sparad källa.
  Den tidigare strukturgruppens 182 paket var kandidater, inte en garanti för
  godkänd tolkning. Övriga kontroller och den smala entrypoint-listan gäller fortsatt.
- Kontroll under lagringen: 0 saknade privata paket och 0 reservationer utan
  dokumenthash/proveniens/kvalitetsmarkeringar.
- API-steget har faktiskt startat och sparat privata per-företag-kvitteringar.
  De första **13** kontrollerna gav `api_no_documents`; det är ingen skattning av
  bortfallet i hela gruppen. Körning 44139154667 pågår fortfarande.
- Fullständig kontroll av de **6 320** AB som vid start saknade bulkkandidat är
  **inte klar**. Högst 1 000 behandlas per körning och återstående hämtas av det
  schemalagda flödet. Senare antal ska läsas i databasen, inte räknas från denna text.
- Den strikta importens återstart 44139154768 avslutades med **success** efter
  kontrollen. Det separata scope-felet är återställt för denna körning, men dess
  grundorsak är fortfarande öppen.
- Underlag för källval för ägar-/koncernuppgifter finns i
  [källundersökningen](ownership-source-research-2026-11-17.md). Ingen ägardataintegration
  eller betaltjänst har startats.


## Verifierad uppföljning 2026-11-17 cirka 23:15 svensk tid

- Körning 44139154667 lyckades vid försök 2 efter det tidigare avbrottet.
  De 100 redan kvitterade API-kontrollerna återanvändes; ytterligare 1 000 sparades.
- Aktuellt urval: 47 889 företag, varav 16 927 AB. Den strikta importen har
  10 417 senaste bokslut, 192 i karantän och 0 väntande kandidater.
  1 473 arkiv är kontrollerade. 6 318 AB saknar bulkkandidat.
- 1 100 API-kontroller är sparade, samtliga `api_no_documents`.
  5 218 AB utan bulkkandidat återstår att API-kontrollera; helimporten av detta
  kompletteringssteg är alltså inte färdig. Schemat behandlar högst 1 000 var fjärde
  timme och hoppar över färska kvitteringar.
- De 192 bulkkompletteringarna består fortsatt av 164 med reservation och 28
  med enbart källa. De ersätter inte verifierade bokslut.
- Verifierad bokslutstäckning bland AB: 10 417 / 16 927 = 61,54 procent.
  Reservationsposter ska redovisas separat och inte räknas som verifierade.
- Täckningskontrollen rapporterar 0 fel i fördelningsvikternas summa.
- Återstarten visar att kvitteringar fungerar; den tidigare API-köavvikelsens
  exakta orsak och det separata SQLSTATE 21000-felet är inte permanent lösta.
- GLEIF har byggts i PR #101 och formaträttats i PR #102. Aktuell status finns i
  [GLEIF-kontrollpunkten](GLEIF.md); uppgiften ovan om att ingen integration
  startats beskriver den äldre kontrollpunkten. Inga betaltjänster används.
