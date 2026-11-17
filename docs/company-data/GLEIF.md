# GLEIF – LEI och redovisningsmässiga koncernrelationer

## Omfattning och semantik

GLEIF används kostnadsfritt under CC0. Källan visar **redovisningsmässigt
konsoliderande moderföretag**, inte en fullständig aktiebok, ägarandelar eller
vilka företag samma individ äger. Inga Allabolag-/UC-/andra betaltjänster används.

Urvalet återanvänder `company_account_scope_members`: företag med säte eller
verksamt arbetsställe i Norrbotten. Fysiska personer (`jurform=10`) och okänd
juridisk form utesluts. Vid start fanns **26 269 juridiska enheter** med giltiga
tiosiffriga organisationsnummer.

Matchningsregel `SE-RA000544-exact-org-1`:

- Sök organisationsnummer med och utan bindestreck, batchvis genom GLEIF API.
- Godta endast exakt organisationsnummer, jurisdiktion `SE` och registerkod
  `RA000544` (Bolagsverket). Ingen namn-/adressmatchning eller fuzzy matchning.
- Flera LEI ger `ambiguous` och väljs inte godtyckligt. En `LAPSED` registrering
  eller inaktiv juridisk enhet behålls med källstatus och varning.
- `not_found` betyder ingen exakt match med **denna registerregel**. Det är inte
  bevis för att enheten saknar LEI eller koncern: andra registerkoder och annan
  identifierarskrivning kan ge bortfall. Särskilt andra organisationsformer än AB
  kan behöva en senare verifierad utökning av matchningsregeln.

## Källor och verifierade kontrakt

- [GLEIF API och officiell dokumentationslänk](https://www.gleif.org/en/lei-data/gleif-api)
- [Kostnadsfri åtkomst och CC0, avsnitt II](https://www.gleif.org/en/meta/lei-data-terms-of-use)
- [Level 2-semantik](https://www.gleif.org/en/lei-data/access-and-use-lei-data/level-2-data-who-owns-whom)
- [Golden Copy](https://www.gleif.org/en/lei-data/gleif-golden-copy/download-the-golden-copy)
- [Officiell registerkod RA000544](https://api.gleif.org/api/v1/registration-authorities/RA000544)

Verkliga kontraktsprov verifierade båda organisationsnummerformaten och kommaseparerade
OR-sökningar, `meta.pagination`, API:s Golden Copy-datum, LEI-fält, direkt-/yttersta
moderrelationer samt rapporteringsundantag. Två offentliga referensbolag matchas
exakt av klienten. Realtida uppgifter loggas inte per företag.

## Flöde, lagring och återstart

`10 · Data · GLEIF – LEI och koncernrelationer` körs manuellt, vid relevant kodändring
och dagligen 02:10 UTC. Varje juridisk enhet kontrolleras normalt efter sju dagar.
Nya företag och avbrutna delsteg återupptas vid nästa körning.

1. Läs aktuellt skyddat urval. Urvalscachen underhålls av befintlig företagsimport.
2. Kontrollera upp till 100 organisationsnummer i varje API-batch, med båda
   skrivsätten. Pagineringsantal och publiceringsdatum måste stämma inom batchen.
   Spara LEI-matchningen efter varje batch. Klienten begränsar sig till högst
   cirka 46 API-anrop/minut och hanterar 429/övergående fel med begränsade återförsök.
3. Hämta det publicerade manifestet och de **versionsbundna fullständiga RR- och
   REPEX-CSV-filerna** en gång per körning som behöver relationsuppdateringar.
   Kontrollera värd, formatversion (`RR_2.1`/`REPEX_2.1`), filstorlek, ZIP-CRC,
   nödvändiga kolumner och fullständigt radantal. SHA256 beräknas på de hämtade ZIP-filerna.
   CSV strömmas och bara rader för matchade urvalsföretag behålls. Globala källfiler
   ligger enbart tillfälligt på körningsmaskinen och blir aldrig Actions-artifacts.
4. Hämta namn och källstatus för berörda moderföretag i batcher, även utländska.
5. Spara direkt och yttersta konsoliderande moderrelation, rapporteringsundantag,
   källperioder, källstatus, valideringsuppgifter och proveniens per företag.
   Relationstolkningen anger aldrig någon gissad ägarandel.
6. Slutkontrollera urval/kö och skriv riktig status/täckning till datakällestatus.
   En ofullständig kontroll får `waiting`, en misslyckad kontroll `failed`.

Migration `0055_company_gleif.sql` appliceras manuellt, inte via Drizzle-journalen.
Tabellerna `company_gleif_versions` och `company_gleif_current` har RLS,
adminläsning och service_role-skrivning. Identitet och relationer har separata
kontrollpunkter. Ändrat innehåll skapar en ny hashbunden version; oförändrat
innehåll uppdaterar bara kontrolltid och senaste proveniens i pekaren. Versionsraden
behåller första observation och första källunderlag.

Payloadens kanoniska UTF8-text verifieras mot SHA256 i databasen. Relationsskrivning
kräver samma identitetshash som den aktuella matchningen. Täckningsfunktionen tar
bara med relationspekare som matchar aktuell identitet. Ett nät-/källfel publicerar
aldrig ett tomt moderföretag och tidigare lagrade versioner raderas inte.

Källproveniens skiljer API:s publiceringsdatum från relationsfilernas publiceringsdatum.
Dessa kan skilja sig åt; det bevaras uttryckligen i stället för att uppgifterna
beskrivs som ett gemensamt ögonblick. GLEIF:s källperioder och observationstid är
inte datum för faktiskt ägarbyte.

## Hur resultaten får användas

- `direct` = direkt redovisningsmässigt konsoliderande moderföretag.
- `ultimate` = yttersta redovisningsmässigt konsoliderande moderföretag.
- `exception` = rapporterat undantag. `NATURAL_PERSONS` identifierar inga personer;
  `NON_CONSOLIDATING` innebär inte att företaget saknar aktieägare.
- `unreported` = ingen användbar aktuell uppgift i dessa källfiler.
- `conflict` = flera olika aktuella moderföretag eller samtidig relation och undantag.
  Ingen godtycklig relation väljs.
- Rader markerade som borttagna/inaktiva/utgångna behålls som historiskt underlag,
  men blir inte aktuell moderrelation. `LAPSED` ger varning.
- Endast urvalsföretagens rapporterade länkar till moderföretag samlas. Detta är
  **inte** ett komplett globalt koncernträd med alla syskon-/dotterföretag.

Kopplingen skriver inte till bokslut, arbetsställefördelning, AFR-historik eller
publikt sökindex. En publik bolagssida ingår inte i detta datainsamlingssteg;
framtida visning måste behålla avgränsning, datum, varningar och okänd-status.
Datakällan blir synlig i befintlig generisk adminöversikt.

## Verifiering och kontrollpunkt

- `python -m unittest discover -s tests -p test_gleif.py`: syntetiska exempel för
  exakt matchning, fel registerkod, dubbla LEI, komplett/stabil paginering,
  historiska relationer, rapporteringsundantag, konflikter, LAPSED, utländska
  moderföretag, CSV-kontrakt/radantal och otillåtna URL:er.
- `NODE_PATH=... node --test tests/company-data-errors.test.cjs`: skyddad route,
  cursorvalidering och befintliga fel-/återförsökskontrakt.
- `tests/company-gleif-protected.sql`: idempotens, SHA-kontroll, rollbehörigheter
  och RLS i en transaktion som alltid rullas tillbaka.

Läs aktuell täckning med `company_gleif_coverage()`. Verifiera separat antal i urval,
kontrollerade identiteter, entydiga matchningar, tvetydiga matchningar, färdiga
relationskontroller, kända moderrelationer och rapporteringsundantag. Matchningsandel
är inte andelen kompletta koncernträd.

### Driftfel och åtgärder 2026-11-17

- Första körningen sparade alla 26 269 identitetskontroller: 1 758 entydiga,
  24 508 utan exakt LEI och 3 tvetydiga. Relationer var ännu inte lagrade.
- Fullständiga CSV-filer saknar `DeletedAt`; kolumnen förekommer i deltafiler.
  PR #102 gör fältet valfritt men bevarar borttagningsmarkeringen när den finns.
  Båda fullfilerna har kontrollerats i sin helhet mot storlek och radantal.
- GitHub-körningen fick därefter HTTP 403 från bulkfilernas primära domän,
  medan API och samma filer fungerade från kontrollmiljön. PR #103 lägger till
  kontrollerade steg och resurstyp i felloggen, utan företagsidentifierare.
- Vid exakt detta bulk-403 får klienten försöka samma versionsbundna sökväg på
  GLEIF:s officiella äldre Golden Copy-domän `leidata-preview.gleif.org`.
  Ingen godtycklig redirect, nyare version eller annan utgivare accepteras.
  Faktisk nedladdnings-URL, SHA256, storlek och radantal sparas i proveniensen.
  Se GLEIF:s [tekniska besked om båda domänerna](https://www.gleif.org/ja/newsroom/blog/getting-technical-number1-it-updates-across-the-global-lei-system-golden-copy-file-download-api).
- Migration `0056_company_gleif_runtime_index.sql` är manuellt applicerad och
  inte journalförd. Ett partiellt index för juridiska enheter undviker
  tiotusentals slumpmässiga heap-uppslag i rikstäckande AFR. Täckningsfrågans
  uppmätta databastid minskade från 13,7 till 1,1 sekunder före relationsimporten.
- En färsk schemakontroll återanvänder redan läst urval och hämtar inga nya
  externa filer när inga uppgifter behöver uppdateras. Detta har regressionstest.

Verifierat produktionsutfall följer nedan. Kontrolltäckning och faktisk
relationstäckning hålls isär.


### Verifierad lagring 2026-11-17 cirka 23:31 svensk tid

- 26 269 juridiska enheter i aktuellt urval; samtliga har sparad identitets- och
  relationskontroll. Detta är kontrolltäckning, inte komplett ägartäckning.
- 1 758 entydiga LEI-träffar (6,69 procent), 24 508 utan exakt träff med denna
  registerregel och 3 tvetydiga. Identiteterna från första körningen återanvändes.
- 203 företag har minst en aktuell konsoliderande moderrelation och 1 566 har
  minst ett rapporteringsundantag. Grupperna överlappar: ett företag kan ha
  moderrelation på en nivå och undantag på den andra.
- 52 538 innehållsversioner finns lagrade, en identitet och en relationspost per
  urvalsföretag. 0 förfallna kontroller, 0 identitetshashfel, 0 saknade
  filhashar, 0 konflikter och 0 aktuella moderlänkar med inaktiv/borttagen eller
  otillåten registreringsstatus. RLS är aktiverat och anonym läsning saknas.
- Källrelease: 2026-11-17 16:00:00. RR: 493 332 rader, 24 522 193 byte, SHA256
  `9ef9abcf0a4219ca12b2c0d8d514b7482b9aacd8647c531d645a678a93bb7c91`.
  REPEX: 6 485 787 rader, 62 845 311 byte, SHA256
  `a1b82fb0f294fe589377a3b28fe846fc1942029a969661aabf823801def72462`.
- Produktionskörning [44189777542](https://github.com/UtvecklaNorrbotten/kompetensarena-norrbotten/actions/runs/44189777542)
  läste denna gång båda filerna via primärdomänen. Det tidigare 403-felet var
  inte permanent denna gång. Reservdomänens båda filer har verifierats separat
  med exakt samma storlekar och SHA256; reservvägen var inte nödvändig i denna
  produktionskörning. Ett regressionstest kontrollerar dess avgränsning.
- PR #104 är mergad som `9f3edf1091ecf6489c5d1a9d6012e5a528c99b92`.
  CI 44189691942 passerade (67 Python- och 7 Node-tester).
- Det kvarstår 5 218 API-kontroller i den separata bokslutskompletteringen.
  GLEIF utökar inte bokslutstäckningen och ger inte fullständiga aktieägarträd
  eller identifierade fysiska ägare. Inga betaltjänster har använts.

### Efterkontroll av fortsatt drift

Produktionskörningen 44189777542 avslutades med **success**, `remaining_due=0`
och fem externa GLEIF-anrop (manifest, två fullfiler och två moderföretagsbatcher).
Datakällestatus uppdaterades till `succeeded`.

Därefter återstartades den tidigare misslyckade körningen
[44188528586, försök 3](https://github.com/UtvecklaNorrbotten/kompetensarena-norrbotten/actions/runs/44188528586).
Den passerade också. Slutloggen visade `remaining_due=0` och `api_requests=0`:
färska kontrollpunkter återanvändes utan ny GLEIF-hämtning. Detta verifierar
flödet efter första helimporten; kalenderutlösningens nästa faktiska körning
återstår förstås att observera. Daglig kontroll är konfigurerad 02:10 UTC,
med förnyelse efter sju dagar per företag.

AFR och profilernas senaste datakällestatus var `no_change`; strikt bokslutsimport
var `succeeded`. Den separata boksluts-API-kompletteringen fortsätter var fjärde
timme. Dess 5 218 återstående kontroller och tidigare odiagnostiserade
SQLSTATE 21000-fel är fortsatt dokumenterade i kompletteringskontrollpunkten.
