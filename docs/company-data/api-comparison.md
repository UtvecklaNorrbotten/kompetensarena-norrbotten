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

PR [#98](https://github.com/UtvecklaNorrbotten/kompetensarena-norrbotten/pull/98) är mergad (`5eb6dc2749b4cbc69d6a71c71ffdde6bbedf6073`). GitHub-körning 44074848618 passerade 46 Python-tester och fyra Node-testfall.

Produktionsjämförelsen [44075854363](https://github.com/UtvecklaNorrbotten/kompetensarena-norrbotten/actions/runs/44075854363) avslutades med **success** 2026-11-17 12:39 svensk tid. Befintlig ETL-miljö kunde då läsa det skyddade urvalet. Resultatet är verifierat mot Bolagsverkets produktions-API med GitHub-hemligheterna, inte mot testdata.

| Grupp | Kontrollerade AB | Med API-dokument | Utan API-dokument |
|---|---:|---:|---:|
| Verifierat bokslut i bulkimporten | 5 | 5 | 0 |
| Ingen kandidat i bulkkatalogen | 5 | 0 | 5 |

De fem importerade företagens dokumentlistor innehöll tillsammans 17 rapporter. Fem senaste paket hämtades: alla hade samma senaste rapportperiod som bulkimporten, alla fem XHTML-dokument kunde tolkas med befintlig företagsparser och samtliga fem XHTML-SHA256 var exakt lika med lagrad dokumenthash. ZIP-paketens SHA256 skilde sig i alla fem fall; identiska använda XHTML-dokument visar varför enbart pakethash inte ska användas som innehållsskillnad mellan leveranssätten. Inga PDF-medlemmar observerades i dessa fem paket. Detta utesluter inte PDF eller andra format i andra API-svar.

Jämförelsen använde 16 API-anrop inklusive token; separat referenskontroll av OAuth/dokumentlista använde två. Endast anonyma summeringar finns i logg och artifact `company-api-comparison.json`. Inga bokslut, kandidater, fördelningar eller källdokument skrevs av jämförelseskriptet. Inga extra rapporter hittades bland de fem bolag som saknades i bulk. Stickprovet är för litet för slutsatser om samtliga saknade företag; ingen större täckningsgrad är därför fastställd.

Publiceringen krävde ett nytt godkännande efter automatiskt granskningsstopp. Användaren godkände uttryckligen publicering i nästa meddelande. Deployment `3b9bab00-e98b-4535-aaa2-c083f28b4f84` för version `f19b0c2e0a49faccf41fd1e91c1e72830c951248` startades därefter och Lovables publiceringspanel kontrollerades: **Published**, med **Publish changes** inaktiverad. Det tidigare publiceringsstoppet är därmed löst.

Ett äldre bulkjobb gav `ETL scope: HTTP 422 (SQLSTATE: 21000)` vid uppdaterat AFR-underlag. Direkt kontroll av urvalsfrågan lyckades därefter och API-jämförelsen passerade; exakt orsak till det äldre felet är inte fastställd. Bulkjobb 44074958116 har återupptagits från sina bestående kontrollpunkter efter godkännandet och pågick vid denna kontroll. Detta ska inte beskrivas som ett verifierat permanent felavhjälpande.

**Driftbeslut:** behåll ordinarie filimport. Den fungerande API-klienten/jämförelsen är tillgänglig för avgränsade kontroller. Automatisk API-import och PDF-tolkning är inte aktiverade; de kräver en separat verifierad importdesign, inte bara lyckad autentisering. En framtida större bortfallsstudie kan använda denna klient, men ska ha en uttrycklig budget för antal företag/anrop.
