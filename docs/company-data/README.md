# AFR-profiler och digitala årsredovisningar

Skyddad ETL, utan ny publik analysvy. JobTech, Vinnova, personalkostnader och kompletterande konkurskällor ingår inte.

## Källkontroll 2026-11-13

- `source-contract-2026-11-13.json` innehåller enbart fältnamn, datatyper, kodtabeller och summeringar från 5 000 verkliga JE och 5 000 AE. Inga namn, adresser eller identifierare.
- AFR OpenAPI: https://apiafr.scb.se/swagger/v1/swagger.json . `namn`, `foretagsnamn`, AE `ben`, `postAdress`, `belagenhetsadress.bGatuAdress/bPostNr/bPostOrt`, `nordKoordinatAdressSW/ostKoordinatAdressSW` och `expImp` är verifierade. `foretagsnamn` är en sträng, inte en lista. Export/import är en gemensam J/N-markering, inte separata export- och importflöden. Okända framtida strängvärden bevaras utan gissad tolkning.
- Bolagsverkets officiella nedladdningssida: https://bolagsverket.se/apierochoppnadata/hamtaforetagsinformation/nedladdningsbarafiler.2517.html . Den publicerade katalogen listar 1 469 veckofiler, totalt 136 322 763 930 byte. Senast listad vecka: 2026/45. Filnedladdning kräver ingen API-nyckel eller avtal. Det är digitalt inkomna rapporter, inte alla företags bokslut.
- Verifierad verklig veckofil `arsredovisningar/2026/45_5.zip`: 182 företagspaket. Samtliga 182 kunde tolkas med minst någon av de sex uppgifterna. Saknade taggade uppgifter: nettoomsättning 81, rörelseresultat 1, årets resultat 7, eget kapital 2, tillgångar 2, medelantal anställda 116. Detta är ett urval bland nyare organisationsnummer, **inte** en täckningsskattning för Norrbotten.
- ZIP innehåller ZIP per organisationsnummer + periodslut; dessa innehåller en eller flera XHTML-filer (årsredovisning, ibland annan handling). HTTP Range verifierades med status 206, exakt Content-Range och ETag/If-Match. Därmed behöver inte hela bulkmaterialet laddas ned.

## AFR – separat skyddad historik

Den befintliga kärnimportens identiteter, strukturtabeller, kanoniska hash och historik bevaras. `afr_profile_versions` innehåller endast nya versioner av namn, post-/besöksadress, adresskoordinater och export/importmarkering. `afr_profile_current` pekar på versionen och innehåller endast senaste telefon/e-post. Kontaktändringar skapar ingen historikversion. Person-/organisationsnummer stannar i `afr_je_ident`; profilnyckel för JE är dess interna UUID.

Samma råsvar som kärnimporten redan traverserar filtreras till tillfälliga gzip-filer på körningsmaskinen. De laddas aldrig upp som Actions-artifact eller bestående rå AFR-kopia. Efter lyckad kärnpublicering jämförs profil-/kontakthashar och bara delta skickas. Vid en första profilbackfill där kärnan inte behöver traverseras gör profilflödet en egen fullständig, count- och källdatumkontrollerad traversering innan första skrivningen. Återstart jämför mot redan lagrade hashvärden. `afr_profile_releases` markerar fullbordad komplettering för ett publicerat AFR-källdatum.

Källdatum och observationstid hämtas från den publicerade kärnsynken. Versionsdatum är observationer, aldrig fastställda datum för den faktiska händelsen. Hela landet omfattas av profilinsamlingen, precis som befintligt AFR.

Händelser hålls isär:

| Händelse | Regel |
|---|---|
| Namnbyte | `namn`, `foretagsnamn` eller `ben` ändras |
| Ändrad postadress | Postadressens innehåll ändras |
| Ändrad besöksadress | Besöksadressens innehåll ändras; bekräftar ingen fysisk flytt |
| Möjlig fysisk flytt | Två befintliga kompletta adresskoordinatpar skiljer sig; även detta kan vara omgeokodning |
| Ändrat säte | Befintlig JE-historiks `säte`; återanvänds |
| Byte av juridisk enhet | Befintlig AE-historiks `juridisk_enhet`; CFAR består |
| Export/import | N→J = tillkomst och J→N = bortfall av markering i registret; inte handelns start/slut |

Första observationen skapar en basversion och får inte beskrivas som namnbyte, flytt eller påbörjad handel. Nollkoordinater behandlas som saknade. Historik före insamlingens start kan inte återskapas från dagens adress.

## Bokslut – senaste tillgängliga per företag

Urval: JE med säte i län 25 **eller** minst ett arbetsställe i län 25, enligt publicerat AFR. Svensk struktur utanför länet ingår också i fördelningen. Alla urvalsföretag behålls i täckningsnämnaren även om digital rapport saknas.

`company_account_archives` lagrar ETag och hash över urvalets medlemskap. ZIP-katalogerna indexeras från hela den tillgängliga perioden så att företag vars senaste rapport är äldre hittas. **Bara metadata** indexeras historiskt; enbart det senaste rapportpaketet per företag hämtas och tolkas. Ett ändrat urval föranleder ny katalogkontroll men inga fullkopior av AFR. Äldre bokslutshämtning kan senare byggas på samma parser/källreferenser; är inte aktiverad.

Urvalsordning: största periodslut, därefter senaste publiceringsvecka i arkivnyckeln. LastModified bevaras men används inte som inlämningsdatum: äldre filer kan ha paketerats om. Flera olika rapportpaket för samma period i samma vecka sätts i karantän eftersom ordningsföljden inte är fastställd. Nyare rättade rapporter byter senaste-pekaren först efter verifierad import; tidigare dokument och extraherade poster behålls. Summeringar använder `company_accounts_latest`, aldrig alla versioner. En ny kandidat som ännu inte tolkats räknas inte som verifierat senaste bokslut.

`company_accounts` lagrar period, valuta, enhet, rapporttyp, företags-/koncernavgränsning, sex värden, dokument-ID, källreferens, paket- och dokument-SHA256, tolkningsversion och faktaproveniens (koncept, context, unit, scale, decimals). Hela använda företagspaketet sparas komprimerat och innehållsadresserat i privat Storage `company-source-documents/accounts/<sha256>.zip`. Databasen kontrollerar att paketet finns; servern verifierar dess checksumma före import.

Parsern accepterar endast uttryckligt mappade standardbegrepp i svenska taxonomin och företagets egna contexts. Koncernvärden fyller aldrig luckor i företagsvärden. Okända taxonomier (inklusive ESEF/utökningar som ännu inte verifierats), okända dimensioner och tvetydiga rapporter ger markerat bortfall/karantän. Felaktigt antagande att alla digitala rapporter går att tolka likadant skulle annars kunna blanda koncern och företag. Saknad uppgift är NULL, noll är 0. Dubbla lika fakta summeras inte; motstridiga fakta blir saknade med en kvalitetsmarkering. Jämförelseår används inte som årets värde.

Belopp normaliseras med originalfaktans scale/sign till hela valutaenheter med Decimal, aldrig binära flyttal. Ingen valutakonvertering eller årsjustering görs. Brytna/förkortade/förlängda räkenskapsår behåller sin faktiska period.

- Rörelsemarginal = 100 × rörelseresultat / nettoomsättning.
- Soliditet (ojusterad) = 100 × eget kapital / totala tillgångar. Ingen justering för obeskattade reserver; detta skiljer sig från vissa leverantörers justerade soliditet.
- Noll eller saknad nämnare ger NULL kvot. Resultat, balansposter och kvoter ligger bara på företagsnivå.

## Fördelningsregler `afr-midpoint-1`

| Storleksklass | Mittpunkt/regler |
|---|---|
| SCB-kod 1, 0 anställda | 0 när positiva vikter finns |
| Slutna intervall, kod 2–15 | (lägsta + högsta) / 2, enligt verifierad kodtabell |
| Kod 16, 10 000+ | Antaget intervall 10 000–14 999, mittpunkt 12 499,5; samma bredd som föregående klass, särskild markering |
| Kod 0, NULL eller okänd | Medianen av företagets positiva mittpunkter; om inga finns: 1. Markeras som imputering |
| Alla arbetsställen med 0 | Lika vikter, markerat reservantagande |
| Ett arbetsställe | Vikt 1 |
| Inga arbetsställen | Ingen arbetsställefördelning; företagsbokslutet behålls |

Vikt = mittpunkt / summan av mittpunkter för **alla svenska arbetsställen**, oberoende av bokslutets medelantal anställda. Avrundningsrest läggs deterministiskt på sista positiva CFAR så att vikter summerar exakt till 1 och fördelad omsättning summerar exakt till företagsomsättningen. Servern verifierar full CFAR-nämnare, historik-ID, viktsumma och omsättningssumma mot AFR innan atomisk skrivning.

Om en komplett AFR-insamlingsperiod finns före bokslutsdagen rekonstrueras arbetsställenas senast observerade tillstånd före periodslutet, inklusive bortfall och byte av JE. Annars används aktuell svensk struktur och märkningen `current_structure_for_older_accounts`. Strukturen sparas som referenser till befintlig AFR-historik, inte som nya AFR-kopior. Vid ny AFR-publicering räknas fördelningen om med samma källdokument. Historisk observation är fortfarande en approximation av faktisk struktur vid bokslutstidpunkten.

Mittpunkter är ett antagande om relativ personalstorlek. Omsättning behöver inte vara proportionell mot personalen: huvudkontor, kapitalintensiva anläggningar och försäljningskontor kan skilja sig kraftigt. All fördelad omsättning har därför `is_estimate=true` och regel-/strukturmarkeringar.

## Drift, återstart och åtkomst

1. Applicera migration `0048_company_data.sql` en gång. Den är applicerad i projektets databas 2026-11-13 (inte tillagd till Drizzle-journalen för automatisk återapplicering).
2. Publicera API-routen `/api/public/jobs/company-data` i Lovables miljö. Endast befintlig ETL-bearer godtas; inga nya nycklar behövs.
3. AFR-workflowet kompletterar profiler efter lyckad kärnsynk. Tillfälliga råsvar och kontaktuppgifter ska aldrig läggas i loggar/artifacts.
4. `10 · Data · Bolagsverket – digitala årsredovisningar` gör begränsade, återupptagbara körningar. Vid avbrott behålls arkivmarkörer, kandidater och redan verifierade bokslut. Nästa körning hoppar över oförändrade kataloger och fortsätter med återstående kandidater. Schemat fortsätter var fjärde timme under uppbyggnaden; färdig källa kräver endast metadata-/statuskontroll tills något ändras.
5. Källstatus registreras i `data_source_runs` + `data_source_state` för `scb-afr-profiles` och `bolagsverket-annual-accounts`. En ofullständig katalog/import ger `waiting`, inte en falsk lyckad helimport.

Alla nya tabeller har RLS med adminläsning och service_role-skrivning. Råa företagspaket ligger i privat bucket utan policy för anon/authenticated. Ingen identitet, adress, kontakt eller rå företagsrapport läggs i publikt sökindex.

## Verifiering

- `python -m unittest discover -s tests -p test_company_accounts.py` – syntetiska exempel för belopp, period, dubbletter, koncern, saknat/noll, alla fördelningsregler och range-skydd.
- `tests/company-data-protected.sql` – transaktionstest med syntetiska profil-/kontaktvärden; idempotens, kontaktöverskrivning utan historik, händelsetyper och åtkomst; alla ändringar rullas tillbaka.
- Befintliga AFR-tester körs fortsatt. Ett upptäckt fel i återupptagningen rättades: tomma R-listan `stats=list()` blev JSON-arrayen `[]`, som API:t avvisade. `stats` utelämnas nu när listan är tom.
- `company_data_coverage()` redovisar urval, ett/flera/inga arbetsställen, saknad digital kandidat, import/karantän, faktaluckor, perioder, strukturgrund och reservregler. Full täckning ska alltid hämtas efter avslutad kataloggenomgång; ovanstående 182 paket är bara formatverifiering.

### Prestandakontroll i skarp drift
Migration `0049_company_data_runtime_indexes.sql` lägger till en kompakt urvalscache med endast interna JE-nycklar. Den räknas om en gång per publicerad AFR-synk, så att paginering inte läser landets strukturtabeller på nytt för varje sida. Den duplicerar inga namn, adresser, identifierare eller strukturegenskaper. Katalog- och importmarkörer behålls vid timeout. En slutkontroll jämför urvalets medlemskap igen; om AFR ändrats under körningen markeras källan `waiting` och ny katalogkontroll krävs.

AFR-finaliseringens frågeplan begränsas i samma migration till hash-join där det finns ett alternativ, med 64 MB arbetsminne. Detta ersätter inte balanskontroller eller historik utan undviker rikstäckande slumpmässig indexläsning för ett avgränsat delta. Upptagna publiceringar pollas separat från budgeten för nya försök. En ofullständig avslutad delkörning visas generellt som ”Väntar på fortsatt import” i admin.

ZIP-kataloger återanvänds under bokslutsläsningen i en begränsad minnescache (högst 64 arkiv) med skydd för samtidiga läsare. ETag ingår i cachenyckeln och varje byteintervall är fortsatt villkorat med If-Match. Tester kontrollerar samtidig läsning, ändrad ETag och att en aktiv läsare inte stängs av cacheutrymning. Ny kod får avbryta och återuppta en bokslutskörning från dess bestående kontrollpunkter; schemalagda kontroller köar fortfarande.

Tolkningsversion `bv-ixbrl-2` bevarar även K2/K3 där det kan fastställas från rapportens officiella schemaRef, tillsammans med ursprungliga entrypoint-URI:er. Ett kompletterande formatprov omfattade 25 andra företagspaket (45 XHTML-handlingar): samtliga 25 årsredovisningar kunde tolkas, inklusive K3; 20 övriga handlingar var inte årsredovisningar och användes inte som företagsbokslut.
