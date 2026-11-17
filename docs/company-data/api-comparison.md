# Bolagsverket API – avgränsad produktionsjämförelse

Klientuppgifter ligger endast i GitHub Actions secrets `BOLAGSVERKET_CLIENT_ID` och `BOLAGSVERKET_CLIENT_SECRET`. Det är produktionsuppgifterna för värdefulla datamängder. Inga testuppgifter blandas in och inga nya Lovable-hemligheter behövs.

## Körning

Workflow: `90 · Kontroll · Bolagsverket – API mot veckofiler`, `.github/workflows/compare-bolagsverket-api.yml`. Kan startas manuellt; push av klient/jämförelsekod på main startar samma avgränsade kontroll. Ingen återkommande schemaläggning aktiveras innan nyttan har verifierats.

Den redan skyddade ETL-routen har läsoperationen `api-sample`. Den väljer upp till fem vanliga svenska AB med verifierat importerat bokslut och fem utan kandidat i befintlig bulkkatalog. Eventuella karantänfall i samma avgränsade urval tas också med, högst fem. Högst tio UUID-sidor med 100 företag granskas. Urvalet är reproducerbart, men inte ett statistiskt representativt stickprov. Ofullständiga/pending kandidater jämställs inte med saknade rapporter.

OAuth client credentials använder produktionens `https://portal.api.bolagsverket.se/oauth2/token`, scope `vardefulla-datamangder:read`, och `https://gw.api.bolagsverket.se/vardefulla-datamangder/v1`. Anropen är POST `/dokumentlista` och GET `/dokument/{dokumentId}`. Dessa adresser fanns i användarens tidigare R-skript och jämförs med aktuella svar. API:t är dokumenterat med OAuth 2 och 60 frågor/minut; klienten använder högst 50/minut, cachar token och gör högst en tokenförnyelse efter 401. 429 och tillfälliga serverfel får begränsade återförsök.

Källor:
- https://bolagsverket.se/apierochoppnadata/hamtaforetagsinformation/vardefulladatamangder/apiforvardefulladatamangder.5513.html
- Användarens R-skript från 2025-07-08.
- Publik kopia av API v1-specifikation: https://hex.pm/packages/bolagsverket_ex/0.1.0/files/API%20Spec.yaml . Den är en tredjepartskopia; faktisk produktionsrespons avgör vad som är verifierat.

## Vad som kontrolleras

Dokumentantal, största rapportperiod och registreringsordning jämförs mot bulkimportens senaste kandidat. Om registreringstidpunkten bara anger dag kan två olika rapporter samma dag inte ordnas säkert. Klienten markerar sådana fall som tvetydiga i stället för att välja listans första dokument.

Endast senaste entydigt valda paket hämtas. Format kontrolleras med ZIP/PDF-signaturer och XHTML-medlemmar; befintlig iXBRL-parser återanvänds utan OCR eller AI-tolkning av PDF. Paketets och den använda XHTML-filens SHA256 jämförs med redan sparade hashvärden där de finns. Olika pakethashar kan bero på ompaketering och är inte ensamma ett värdefel.

Kontrollen är read-only för företagstabeller och privat Storage. Nedladdade källpaket och dokumentlistor hålls i körningsminnet; inga sådana filer, identiteter, dokument-ID:n, token eller fria felpayloads laddas upp. Endast anonyma gruppsummeringar sparas som `company-api-comparison.json` med 30 dagars retention. Credentials tillåts inte följa HTTP-omdirigeringar. Testerna använder enbart syntetiska uppgifter.

API-svar med okänt schema räknas som fel, aldrig som tomma dokumentlistor. Att API saknar dokument i ett litet urval bevisar inte att alla resterande företag saknar API-dokument. Att ett äldre bokslut återfinns bevisar inte täckning för senaste räkenskapsåret.

## Återupptagning

1. Läs denna fil, AGENTS.md och senaste Actions-körning.
2. Kontrollera att `api-sample` är publicerad i samma miljö som `ETL_BASE_URL`. Jobbet väntar högst cirka tre minuter om en push hann före API-publiceringen.
3. Kör jämförelsen och granska endast summeringsfilen/loggen. Ingen fullständig bokslutsimport ska startas för detta test.
4. Dokumentera faktiskt resultat här före beslut om en automatisk API-import eller utvidgad PDF-hantering.

## Kontrollpunkt 2026-11-17

PR #98 är mergad (`5eb6dc2749b4cbc69d6a71c71ffdde6bbedf6073`). GitHub-körning 44074848618 passerade 46 Python-tester och fyra Node-testfall. OAuth och dokumentlistan verifierades sedan mot produktion i körning 44075465422, med de konfigurerade GitHub-hemligheterna: `oauth_verified=true`, `document_list_verified=true`, en referensrapport i listan och två HTTP-anrop. Varken klientuppgifter, token eller rå API-payload skrevs ut.

Jämförelsen mot databasurvalet är ännu inte verifierad: körningen misslyckades vid ETL-läsoperationen `api-sample`. Den bredare API-täckningen och dokumentformaten får därför inte påstås vara fastställda. Ett separat, redan befintligt bulkjobb gav dessutom `ETL scope: HTTP 422 (SQLSTATE: 21000)`; dess orsak är inte utredd i detta API-uppdrag.

Publiceringen av den nya Lovable-versionen blockerades av automatisk godkännandegranskning, som krävde separat publiceringsgodkännande eftersom produktionshostingen påverkas. Ingen kringgång utfördes. Den konkreta versionen finns på main; inga produktionsbokslut har skrivits av jämförelseskriptet. Efter att publiceringen är godkänd och verifierad ska workflowet köras på nytt och det faktiska resultatet dokumenteras här.
