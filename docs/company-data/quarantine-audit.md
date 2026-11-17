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
