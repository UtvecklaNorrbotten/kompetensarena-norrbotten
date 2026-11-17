# Karantänkontroll mot Bolagsverkets API

## Kontrollpunkt 2026-11-17

Databasen hade 192 karantänkandidater, samtliga med den övergripande felkoden
`unsupported_or_ambiguous_company_report`. Den koden beskriver inte orsaksfördelningen.

`90 · Kontroll · Bolagsverket – karantän mot API` inventerar alla karantänkandidater
(AB inklusive bank-/försäkrings-AB), hämtar redan sparade privata paket med
SHA256-kontroll och jämför med senaste entydigt identifierade API-rapporten.
Detta är en läsande undersökning: inga bokslut, kandidatstatusar eller senaste-pekare
skrivs. API-klientens gräns är 50 anrop/minut inklusive återförsök.

Kontrollen skiljer mellan paketens kontrollsummor och XHTML-dokumentens innehåll.
Ompaketerade ZIP-filer är inte i sig en rättad rapport. Parserfel räknas per dokument
och per företag; avvisade bilagor kan förekomma även i ett giltigt paket.

Resultatet sparas som summeringar i `company-quarantine-audit.json` i körningens
artifact och i loggen, utan identifierare, källvärden, dokument eller signerade URL:er.
Företagsunderlag och dokument hålls i minnet. Vid avbrott finns senaste summeringen
kvar; detta är ingen importkontrollpunkt och en ny diagnoskörning gör om läsningen.
Uppgifterna gäller inventeringen vid kontrollens start. En samtidig ordinarie import
kan ändra kandidatstatusar; därför ska aktuell databasstatus kontrolleras efteråt.

Resultat och rekommenderad hantering kompletteras efter faktisk produktionskörning.

## Faktiskt resultat 2026-11-17, 16:38–16:45 svensk tid

- Första körningen: [44113720249](https://github.com/UtvecklaNorrbotten/kompetensarena-norrbotten/actions/runs/44113720249).
  Alla **192** sparade paket verifierades mot SHA256. Samtliga tillhör aktuellt
  Norrbottensurval: 191 vanliga AB och ett bankaktiebolag.
- API:et listade dokument för **191** företag, med samma senaste period som
  bulkkandidaten. Ett företag saknade dokument i API-listan.
- **190** API-paket hämtades och undersöktes framgångsrikt. Alla 190 hade **exakt samma
  uppsättning XHTML-kontrollsummor** som respektive sparat paket och samma parserutfall.
  ZIP-kontrollsummorna skilde sig i alla 190 fall: ompaketering ändrade inte XHTML.
  Ingen av dessa 190 blev tolkningsbar genom API-hämtningen.
- För **ett** företag med API-dokument kunde hämtning/diagnos inte slutföras.
  Den första kontrollen saknar en säker uppdelning mellan anrops- och diagnosfel.
  Detta fall är fortfarande oavgjort; körningen avslutades avsiktligt med felstatus
  och `complete=false`. Den får inte redovisas som 192 lyckade API-jämförelser.
- 385 API-anrop inklusive token/återförsök; ingen PDF observerades bland de
  framgångsrikt undersökta paketen. Ingen fullständig API-import byggdes.
- [Fullständig anonym summering](quarantine-api-results-2026-11-17.json).

### Tolkningshinder

| Parserhinder | Företagspaket | XHTML-dokument |
|---|---:|---:|
| Saknad `FinansiellRapportList`-deklaration som parsern godtar | 188 | 218 |
| XML-skydd stoppar dokumentet | 2 | 2 |
| Saknad/tvetydig period för det förväntade periodslutet | 2 | 2 |
| Saknad/motstridig rapportvaluta bland godtagna fakta | 2 | 2 |

**Kategorierna överlappar.** Bilagor kan sakna rapportdeklaration samtidigt som en
annan handling i samma paket har ett annat hinder. Tabellen är ingen disjunkt
orsaksfördelning och innebär inte att källrapporten nödvändigtvis saknar valuta.

En andra, **enbart läsande kontroll av sparade dokument** lyckades för alla 192:
[44117104479](https://github.com/UtvecklaNorrbotten/kompetensarena-norrbotten/actions/runs/44117104479).
Den gjorde inga nya Bolagsverks-API-anrop.

- **182 paket** innehåller XHTML med en K2-sökväg i schemaRef, kända bokslutsbegrepp
  i accepterade namnrymder, matchande företagsidentifierare och förväntat periodslut,
  utan dimensioner i dessa slutdatumkontexter, men utan `FinansiellRapportList`.
  Detta är den tydligaste kandidaten för en riktad förbättring av parsern.
- Två dokument stoppades av **DOCTYPE**, inte av en observerad ENTITY-deklaration.
  Skyddet har inte lättats och DTD:n har inte tolkats.
- Två K2-markerade dokument har ingen matchande kontext för förväntat periodslut.
- Två K3-markerade dokument har matchande kontexter men stoppas i valutakontrollen.
- Övriga observerade handlingar har inga av de sex igenkända måttbegreppen och
  saknar en klassificerad K2/K3-entrypoint. Dessa kan vara bilagor och ska inte
  automatiskt behandlas som årsredovisningar.
- [Struktursummering](quarantine-structure-results-2026-11-17.json).

### Rekommenderad hantering och återstående arbete

1. Prioritera validerat stöd för K2-dokument utan just `FinansiellRapportList`,
   med betrodd, verifierad officiell entrypoint och kontrollerad företagsidentitet,
   period och företags-/koncernavgränsning. **182 är en kandidatgrupp, inte 182 nya
   verifierade bokslut.** Strukturkontrollens K2-klassificering bygger på URI-sökväg;
   en ändrad importregel måste även verifiera värd och taxonomikontrakt. Att alla
   K2-markerade filer automatiskt är säkra att importera är ännu obevisat.
2. Granska de två DOCTYPE-fallen separat. Ett säkert stöd får inte aktivera
   externa DTD-/entitetsuppslag eller generellt ta bort XML-skydden.
3. Kontrollera periodmetadata och de två K3-valutafallen mot sparade källor;
   välj inte jämförelseår, godtycklig valuta eller koncernvärden som reserv.
4. Behåll karantän för handlingar utan tillräckliga årsredovisningsfakta.
5. Följ upp det enda ofullständiga API-fallet med säkert klassificerad felorsak.
   Nuvarande summeringar innehåller avsiktligt inga identifierare för riktad återstart;
   en framtida per-företag-kontrollpunkt måste lagras privat, aldrig i publika artifacts.
   Det behövs ingen ny fullständig katalog-/bokslutsimport för utredningen.

Ingen parserregel, bokslutspost, kandidatstatus eller senaste-pekare ändrades av
kontrollerna. Alla **192 ligger kvar i karantän** tills respektive källa kan tolkas
med verifierade regler. Befintliga källpaket och tidigare verifierade versioner
bevaras. Kod från PR #99 är mergead och skyddad diagnosroute publicerad.
Validering: 50 Python- och 5 Node-tester passerade i PR; den separata
strukturkontrollen passerade ytterligare två syntetiska tester i produktionskörningen.
