## Tillägg: CSV-paket jämfört med nationell staging, 2026-11-06

Det skrivskyddade stagingtestet bekräftar 1 235 identiska CSV-/stagingobservationer för
Riket/LTU/uni:171, Kvinnor/-24/2025-26. Det nationella stagingurvalet omfattar 9 731:
8 496 observationer för andra lärosäten saknas i CSV-deluttaget. Deluttaget är korrekt
inom sitt begärda urval men ofullständigt för det nationella jobbet och får inte färdigställa det.
Ingen stagingrad ändras. Se `uka-csv-staging-audit-2026-11-06.json` och
`scripts/uka_csv_staging_audit.py`. Detta är en integrationskontroll; CSV-importören
för hela kampanjen är ännu inte implementerad.

> Nyaste källverifiering 2026-11-06: breda HST-CSV-uttag fungerar. 857 nationella
> observationsnycklar/värden matchar JSON exakt. Gemensamma lärosätesuttag matchar
> disjunkta uttag exakt (14 705 respektive 14 975 observationer i två läsår).
> 144 uni:171- och 366 LTU-observationer matchar också JSON, liksom fyra källtotaler.
> Det visar att den tidigare hypotesen om generellt trasig CSV-export var för bred.
> Minimala nollbytesvar kvarstår som historisk evidens; intern orsak är okänd.
> Senare minimikontroller blockerades av lokal proxy och ger ingen källslutsats.
> Nästa steg är CSV-paket med fulla dimensioner per period/lärosäten, anslutna till
> stagingkontrollerna. Den stora JSON-budgetökningen startades inte.
> Läs UKA_RESTART.md och uka-csv-bulk-evidence-2026-11-06.json först.

> Senaste genomförande 2026-11-06: fryst tioårsplan med 1 305 urval och ett
> stagingjobb per indikator (högst två samtidigt). Körning 42228224045 passerade;
> 48 urval och 25 342 observationer är kontrollerade och sparade i filbaserad staging.
> Lokal nollbudgetåterstart bevarar samtliga tio kontrollsummor med 0 nya API-anrop.
> 72 lokala tester passerar. Ingen databas/publicering används. Full källtäckning,
> källversion och tomsemantik är fortfarande olösta. Läs UKA_CAMPAIGN.md först.

> Nyaste läge 2026-11-06: Actions 42223602896 passerade. Samtliga tio indikatorer
> stöds nu av den återstartbara diagnostikkön. HST:s 24 kön/ålders-/periodgrafer ger
> 288 exakta referensmatchningar. De övriga nio har 18 godkända period-/lärosätesprov
> och nio avslutade nationella grafer (4 600 observationer, noll dubbletter).
> Examinerade kräver även Inriktning; stöd och separat verifierad kö är tillagda.
> Programutbudet beror på period: indikator 135:s Agronomexamen 2012/13 (41,3)
> saknas i senaste periodens programlista. Periodvisa rotjobb behövs.
> Detta ger inte full tioårstäckning eller tillstånd till publicering.

> Senaste verifiering 2026-11-06: Actions 42217378947 passerade. Hela annonserade
> studieform-först-grafen för Riket/Kvinnor/-24/2025-26 är avslutad: 857 noder,
> 9 731 observationer, inga väntande och inga fel. Metadata-audit ger noll dubbletter
> och noll ogiltiga ämnesvägar. 222 av 230 metadataämnesvägar finns i urvalet;
> åtta ej annonserade vägar återstår att förklara. Full källtäckning och publicering
> är fortfarande inte godkända. Se UKA_RESTART.md och uka-hst-coverage-2026-11-06.json.

> Uppdatering 2026-11-06: en separat `study-first`-strategi undviker de tvetydiga
> Ämne→Studieform-länkarna genom att välja Studieform vid roten. Båda Övrigt-grenarnas
> värden och ämnesgrupper är verifierade. 48 smågrafsobservationer är exakt lika referensen.
> Ett större lokalt prov nådde 54 noder/1 199 observationer utan fel, men grafen är ofullständig.
> Se UKA_RESTART.md och uka-study-first-evidence-2026-11-06.json. Ingen produktion är ändrad.

# UKÄ: källutredning och importarkitektur

Datum: 2026-11-06. Arbetsgren: `fix/uka-verified-checkpoint-import`, PR #82.
Status: diagnostik implementerad, importmetod och produktionspublicering **inte godkända**.
Ingen ändring av produktionsimport, databasschema eller produktionsdata i denna gren.

## Aktuellt resultat: JSON-kontextkonflikt blockerar fortsatt hämtning

Den större fortsättningen från sparad artefakt stoppade i körning **42210008954** efter
41 noder och 1 038 sparade observationer. Koden 1051/Övrigt förekommer under både
Medicin och odontologi (914) och Naturvetenskap (915). JSON-noden för det medicinska
delområdet annonserar dubbla studieformsetiketter. Direkta barnanrop för Fristående kurser
ger 38,1 HST med medicinska ämnesgrupper respektive 56,2 HST med naturvetenskapliga ämnen.
Detta är en verifierad kontextkonflikt i vårt JSON-uttag; samband med CSV-felet är inte fastställt.

Metadata-parser version 2 bevarar båda föräldraplaceringarna i stället för att skriva över en.
JSON-kömotorn gör selektiva återförsök av tillfälliga nätverksfel men blockerar datakonflikter.
Körning **42211247897** passerade alla **35 enhetstester** och återställde den blockerade kön
utan nya API-anrop. Källsteget förblev korrekt rött (`blocked_source_error`), med oförändrade
1 038 sparade observationer. Ingen merge eller produktionsimport har gjorts.

Läs `UKA_RESTART.md` och `uka-source-context-conflict-2026-11-06.json` före nästa körning.
Den blockerade noden får inte öppnas genom att summera, slänga eller godtyckligt ge nya nycklar åt
de dubbla etiketterna. Fullständig hierarkikontext eller ett korrigerat källuttag måste verifieras först.
Felunderlaget till UKÄ är kompletterat men inte skickat.

## Uppföljning: webbexport och JSON-alternativ

### Uttömmande, avgränsat HST-prov

Nästa verifieringssteg har genomförts för uni:171, Kvinnor, 2025/26 och
åldrarna Total, -24, 25–34 och 35–. Samtliga annonserade ämnes- och studieformslänkar
följdes tills inga obesökta noder återstod: 12 noder per ålderskategori,
**48 unika observationer**, inga dubbla observationsnycklar.
Varje länkad observation jämfördes med barnanropets faktiska källvärde.
Ämne-först och studieform-först gav exakt samma observationsnycklar och värden.
Den andra genomgången behövde **0 nya källanrop**.
De fyra separata källtotalerna är 61,5; 14,4; 24,2 respektive 22,9 HST.
De har inte summerats fram. Resultatet finns i `uka-hst-complete-2026-11-06.json`.

Detta är ett komplett prov av **den annonserade JSON-grafen för detta avgränsade urval**.
Det bevisar inte att API:t annonserar alla observationer som finns i UKÄ:s underliggande databas,
och det finns ännu ingen fungerande oberoende CSV-referens för värdejämförelse av hela urvalet.
Överensstämmelsen med PR #81:s 48 rader är bara en rimlighetskontroll, inte en värdeverifiering.

Den konservativa planeringsgränsen för HST är 10 perioder × 3 kön × 4 ålderskategorier
× 5 studieformsval × 231 ämnesval = **138 600 nationella gruppanrop**.
Det är inte ett uppmätt behov eller en körtidsprognos. Glesa grupper, kanoniska länkar,
källans hela tidsserier och lärosäteslistorna i Rikets svar kan minska hämtningen.
Ingen multiplikation med antalet lärosäten ska göras blint.

Ingen stor tioårshämtning startas på denna övre gräns. Nästa steg är en deterministisk
manifestplan med återanvändning över perioder och mätning av faktisk mängd noder innan full körning.
Källversion/revisionshantering och oberoende referens måste också lösas före publicering.
`uka_hst_complete_probe.py` har en fast budget på högst 80 nya anrop och stopp vid oväntad grafstorlek.
Tre nya regressionstester kontrollerar alternativa vägar, ändrade värden och motstridiga dimensionsnycklar.

Den 6 november testades UKÄ:s riktiga webbformulär för HST, Riket och enbart källtotaler.
Både 2025/26 och 2024/25 gav faktiskt nedladdade CSV-filer på **0 byte**.
För 2025/26 matchar webbens filtervärden klientens, och samma cachefilnamn returneras.
2024/25 provades först via webbgränssnittet i denna undersökning; det var inte en upprepning av vårt tidigare minimala CSV-anrop.
Det bevisar inte att servercachen är oskyldig eller att UKÄ:s alla exporter är trasiga.
Råa browser-requestbytes har inte fångats. Reproducerbart felunderlag finns i
`uka-export-felunderlag-2026-11-06.md` och har **inte skickats** till UKÄ.

JSON-API:t är en fungerande kandidat till reservkälla:

- Alla tio indikatorer gav källans egna totalvärden för både senaste och äldsta period i vårt valda tioårsurval (fem år för indikator 136 där källfiltret erbjuder det).
- Sex HST-stickprov passerade för Riket, LTU och uni:171 under 2025/26, 2024/25 respektive 2016/17.
- Kön och ålder bevarades när API:ts egna länkar följdes genom studieform, ämnesområde, ämnesdelområde och ämnesgrupp.
- För uni:171, 2025/26, verifierades hela matrisen Kvinnor/Män/Total × -24/25–34/35–/Total: **12 källobservationer** utan konstruerade totaler.
- För de fyra lärosätesproven överensstämde totalvärdet exakt mellan direkt lärosätesanrop och motsvarande observation i Rikets lärosäteslista.
- Ämne → studieform och studieform → ämne gav samma serie med faktiska årsvärden. API:t kan hänvisa båda vägar till samma kombinerade endpoint, vilket redovisas explicit och inte beskrivs som en oberoende CSV-referens.

`group_slug` får inte antas beteckna bara en dimension. API:t returnerar nya sluggar för kombinationer.
Exempel från källan: uni:171, Kvinnor, -24, 2025/26 ger 14,4 HST totalt och
11,6 inom Humaniora och teologi på Generella program. Den kombinerade länken bevarar båda gruppvalen.
Skriptet `scripts/uka_json_probe.py` följer annonserade länkar, jämför källvärden,
kontrollerar att kontextfilter inte försvinner och återanvänder kontrollsummade svar.
Dess sex nya enhetstester kompletterar de tio befintliga. Källprovet har en fast total budget
på högst 74 nya JSON-anrop (20 periodkontroller, 42 HST-länkanrop, 12 kön/åldersanrop).
Källsvar sparas i diagnostikartefakter, inte som dubbla rådatakopior i git.
Resultat och svarsfingeravtryck finns i `uka-json-probe-2026-11-06.json`.

Detta verifierar **stickproven**, inte en komplett alternativ import. Före byte av källa återstår:

1. Fullständig traverseringsplan för historiska ämnen, studieformer och lärosäten för alla tio indikatorer, inklusive sådant som saknas senaste året.
2. Verifierad skillnad mellan saknad grupp, nollvärde, sekretess/null och tekniskt fel.
3. Jämförelse med oberoende referensexporter för samtliga logiska observationer, inklusive källans precision.
4. Volymberäkning innan större hämtning. HST har upp till 5 × 231 dynamiska kombinationer; tio år × tre kön × fyra ålderskategorier kan innebära många API-anrop även om lärosäten hämtas tillsammans från Rikets gruppsvar.
5. Källversion/revisionshantering och publiceringsspärrar enligt arkitekturen nedan.

Grönt i `uka-json-probe.yml` betyder godkända begränsade prover. Det får aldrig användas som automatiskt godkännande för produktionsimport eller merge av hela importlösningen.

## 1. Verifierad felkedja och kvarstående osäkerhet

Granskade körningar:

| Körning | Faktiskt utfall |
| --- | --- |
| 42041479155 | Stopp vid HST 2025/26, uni:171, Kvinnor, age:8 efter rekursiv uppdelning och upprepade tomma exporter. |
| 42092473264 | Ämnesuppdelning före lärosäten leder vidare till tomt urval även för Riket; HTTP 500 förekommer också. |
| 42100723178 | Lärosätesuppdelning före ämnesuppdelning löser inte uni:171. Rubrikfil behandlas som fel och stoppar importen. |
| 42106921717 | Diagnostik lyckas, publicering hoppas över. Riket: 3 420 referensobservationer är exakt lika med 1 731 + 1 689 delobservationer. Uni:171: full export misslyckas, två deluttag ger 36 + 12 rader. Ingen verifierbar full referens för detta urval. |

Körning 42106921717 jämför observationsinnehåll inklusive värden, inte bara antal.
För Riket rapporteras noll avvikande observationer och noll identiska dubbletter.
För uni:171 visar separata åldersuttag samma observationer som motsvarande åldersurval i deluttaget.
Det bevisar **inte** att alla möjliga ämnesobservationer finns för alla perioder/lärosäten/kön.
Dubblettkontrollen i det äldre forskningsskriptet inkluderar dessutom värdet i nyckeln;
den upptäcker inte två olika värden för samma dimensionsnyckel. Den nya kontrollen gör det.

Två viktiga skillnader förklarar varför reservvägen inte reproducerar den lyckade diagnostiken:

1. PR #81 använder alternerande ämnesval i två delar (`1,3,5…` respektive `2,4,6…`).
   Produktionskoden använder sammanhängande halvor och fortsätter dela båda dynamiska grupperna.
   Det är olika frågor till UKÄ, inte två implementationer av samma verifierade urval.
2. Rubrikfiler från smala ämnesurval utlöser samma fel som nollbytefiler och HTTP-fel.
   Alla reservgrenar måste lyckas, även när ett lärosäte legitimt saknar observationer för ett ämne.
   Därför fortsätter rekursionen tills en enskild kombination stoppar hela indikatorn.

Enbart ökade volymer förklarar alltså inte felet. Källa och klient måste särskiljas:

| Svar | Tillåten tolkning |
| --- | --- |
| HTTP-/transportfel, saknad fileUrl, nollbytefil | Tekniskt misslyckande. Aldrig noll observationer. |
| CSV med förväntade rubriker och inga rader | Kandidat till legitimt tomt urval. Kräver stöd från ett oberoende, bredare referensuttag. |
| Giltig CSV med data | Ett lyckat uttag. Fortfarande inget bevis för fullständighet. |
| Samma antal men olika nycklar/värden | Felaktigt resultat. Publicering spärras. |

**Ny observation den 6 november:** små källuttag ger nollbytefiler både lokalt och i GitHub Actions.
Även ett minimalt HST-uttag (2025/26, Riket, Total för kön/ålder/studieform/ämne) ger HTTP 200 och 0 byte.
UKÄ:s separata JSON-API returnerar samtidigt källtotalen **341 246,6** för Riket 2025/26.
JSON-API:t ger **139,5** för uni:171 samma läsår. Dessa värden har hämtats från UKÄ, inte summerats.
Detta stödjer att det aktuella exportproblemet inte är ett bevis på saknade HST-data.
Den interna orsaken i UKÄ:s PHP/exporttjänst är inte verifierad.

Den slutliga kontrollkörningen 42185017866 bekräftar nollbytefiler för **samtliga tio**
minimala indikatoruttag, medan det oberoende JSON-API:t returnerar totalvärden för samma perioder.
Den befintliga R-klienten misslyckas också med det minimala HST-uttaget efter tre försök
(jobb 127783245416). Felet kan därmed inte förklaras enbart av den nya Python-klienten.
Kontrollresultat och värden finns i `uka-source-control-2026-11-06.json`.

Kontroller av alternativa gruppindex (webbgränssnittets JavaScript numrerar om grupper),
indexerade formulärfält samt normalisering av dubbla snedstreck i fil-URL gav inte fungerande minimala exporter.
Ingen av dessa hypoteser används därför som produktionsfix.
API:ts fileUrl är cachebaserad: upprepad identisk POST gav samma dagsbaserade fil-URL.
Den äldre kommentarens antagande att varje POST skapar en ny fil är inte korrekt för dessa försök.

## Ämneshierarkin

HST:s källfilter innehåller två dynamiska grupper:

- Studieform: UKÄ:s Total plus fyra studieformer.
- Ämne: UKÄ:s Total plus 9 ämnesområden, 41 ämnesdelområden och 179 ämnesgrupper.

Exempel från faktiska källtoken: `910_` är en rot, `921_910` dess barn och `922_921` barnbarn.
Den sista delen är närmaste förälder, inte hela släktkedjan. Antalet understreck visar inte nivån.
Det nya skriptet bygger nivån genom föräldralänkarna och kontrollerar saknade föräldrar och cykler.
Totaler och nivåer är skilda observationer. De får aldrig summeras över nivåerna.

## PR #72–81

| PR | Bedömning |
| --- | --- |
| 72 | Utvidgar policy till tio år och alla erbjudna lärosäten/åldrar. Filterutbud bevisar inte observationstäckning. |
| 73 | Ny exportbegäran och perioddelning. Saknar beständig återstart och skiljer inte tomtyperna. |
| 74 | Lärosätesdelning. Ett legitimt tomt smalt urval stoppar fortfarande allt. |
| 75 | Forskningsgren för filter. Inte en färdig import. |
| 76 | Separata källkön och validering före publicering. Nödvändigt skydd, otillräcklig täckningskontroll. |
| 77 | E3/AFR, inte UKÄ-fix. Ger relevanta mönster för importnyckel, staging och återupptagen publicering. |
| 78 | Forskningsgren för uni:171. Visar betydelsen av ämnesurval. |
| 79 | Dynamisk uppdelning, men syntetiska tester modellerar inte legitima tomma hierarkiska kombinationer. |
| 80 | Byter delningsordning. Live-testet kördes och passerade i PR-körning 42100422383 (jobb 127501440578). Det provar ett gemensamt uttag för tre lärosäten och ett läsår, inte alla rekursiva delurval som uppkommer i produktionskörningen. Att steget är överhoppat i push-körningen är avsiktligt och inget fel i grenvillkoret. |
| 81 | Läsande observationstest. Kan bli grönt trots misslyckad referensexport: fel fångas, jämförelser hoppas över och skriptet saknar slutlig assertion för alla obligatoriska kontroller. Behåll som forskning. |

## 2. Rekommenderad workflowarkitektur

Ett samordnande workflow kan användas för tio års historik, men **inte ett enda sekventiellt API-jobb** för allt.
Föreslagen kedja: planera → hämta per indikator → validera per indikator → publicera seriellt → verifiera publicerad täckning.

| Del | Ansvar |
| --- | --- |
| Planering | Spara exakt period-/lärosätes-/köns-/ålders-/dimensionsurval och strategi/version. Registrera källans begränsningar. |
| Källkontroll | Verifiera ett litet känt totaluttag mot JSON-API före större exporter. Stoppa tekniska fel utan rekursionsstorm. |
| Hämtning | Eget jobb och manifest per indikator, högst två samtidiga källjobb, `fail-fast: false`. |
| Uppdelning | Börja med källperiod och källkön. Välj begränsade lärosätesblock. Separat verifierad ämnesstrategi för HST och examenshierarkin 108. |
| Återstart | Deterministisk delnyckel för exakt urval + strategiversion + kampanj/källversion. Hoppa endast över verifierade, checksummeidentiska filer. |
| Validering | Jämför faktiska observationer och källtotaler, period-/dimensionsmanifest och logiska nyckeldubbletter. |
| Publicering | En komplett indikator åt gången; inga hemligheter i hämtnings-/PR-jobben. Ofullständigt manifest kan inte finaliseras. |
| Efterkontroll | Läs tillbaka aktiv batch och faktisk täckning, kontrollera aggregat och källtotaler. Behåll föregående snapshot till godkänd efterkontroll. |
| Status | Separat `failed`, `blocked`, `verified`, `published` och `no_change`. Summan av tio indikatorstatusar får inte ersättas av enstaka framgång. |

Alla indikatorer behöver inte samma strategi. 99, 136 och 77 erbjuder bara ålderstotal.
33 och 108 har hierarkier; de övriga dynamiska programurvalen är enklare.
Alla tio erbjuder Kvinnor, Män och Total i det inventerade filtret.
Erbjudna historiska lärosäten ska inte filtreras bort för att de saknar nutida observationer.

UKÄ:s metadatahash identifierar filterstrukturen, **inte säkert en version av statistikvärdena**.
Ett godtyckligt snapshot-ID eller oförändrad metadata får inte ensamt godkänna gammal cache för publicering.
Publiceringsvägen behöver en verifierbar källversion eller förnyade referens-/totaluttag över hela kampanjen.
Kvartalsvis full revisionskontroll och lätta kontroller mellan dessa bör ersätta veckovisa blinda fulluttag.

### Återanvänd befintliga mönster, inte fel lagringsmodell

- `R/etl/e3_municipal.R`: deterministisk importnyckel, chunkplan, progress, källversionskontroll före finalisering.
- `R/etl/afr_sync.R` och `afr_publication.R`: återuppta komplett staging innan ny källhämtning; idempotent finalisering och bevarad staging vid övergående fel.
- `R/etl/uka_sync.R`: start skapar ny batch, chunks har checksumma, men abort raderar staging och ingen progress-/resume-endpoint finns.
- `src/lib/uka-etl.server.ts`: finalize växlar aktiv batch och anropar därefter aggregatomräkning. Ett omräkningsfel kan inträffa efter att bytet redan skett.
- `drizzle/migrations/0037_uka_nongeographic_storage.sql`: atomiskt aktivt batchbyte, idempotenta chunks/finalize och radräkning. Gammal batch raderas vid finalisering. Detta skyddar mot halvlevererade chunks, inte mot ett från början ofullständigt källurval.
- `drizzle/migrations/0046_uka_incremental_refresh.sql`: bara ändrade indikatorers aggregat räknas om; omräkningslåset och markören bör behållas.

## 3. Implementerat och kvarvarande kodarbete

Implementerat i PR #82:

- `scripts/uka_source_audit.py`: strukturerad filter-/hierarkiinventering; klassificering av CSV-svar; exakta nyckel-/värdejämförelser; bevarade källtotaler; kontroll av att begärda filter respekteras.
- Checkpoints med råa källfiler, urval, metadatahash, SHA-256 och atomisk filskrivning. Korrupta filer och felaktiga/tomma svar återanvänds inte som lyckade uttag.
- Minimal exportkontroll mot oberoende JSON-total före större uttag. En utebliven kontroll spärrar fortsatt hämtning.
- `.github/workflows/uka-source-audit.yml`: separat jobb för alla tio indikatorer, obligatoriska enhetstester, artefakter och GitHub-sammanfattning även vid fel. Inga publiceringshemligheter eller publiceringsanrop.
- `tests/test_uka_source_audit.py`: tio tester för bland annat samma radantal med ändrat värde, dubbla dimensionsnycklar, tomtyper, trasig CSV, ignorerade filter, hierarki, cacheskada och stopp före tunga uttag.

Återstår före en produktionslösning:

1. Fungerande minimal export eller en verifierad alternativ fullständig källa.
2. Oberoende referenser även för uni:171 och flera äldre perioder, samt separata åldersuttag och hierarkinivåer. Ett litet verifierat urval bevisar inte en hel tioårssnapshot.
3. Beständig fullständig hämtningsplan per indikator med täckningskrav per del; hantering av legitima tomma delurval via positiv referensbevisning.
4. UKÄ-specifika start/resume/status-endpoints och databasstöd för importnyckel/manifest. Ofullständig staging ska bevaras för återstart utan att bli publik.
5. Kontrollerad, separat publicerare med manifestspärr, skydd mot äldre kampanjer och bevarad föregående batch tills aggregat och efterkontroller godkänts.
6. Ersätt den nuvarande automatiska push-importen med validering; produktionspublicering ska vara ett uttryckligt steg efter godkänt manifest.

## 4. Beviskrav och teststatus

Lokalt: tio enhetstester passerar. De är test av kontrollmekanismer, inte bevis för UKÄ-datatäckning.
Första live-kampanjen: https://github.com/UtvecklaNorrbotten/kompetensarena-norrbotten/actions/runs/42184028162.
Slutlig kampanj med minimal oberoende kontroll, begränsning av fortsatta uttag och R-kontroll:
https://github.com/UtvecklaNorrbotten/kompetensarena-norrbotten/actions/runs/42185017866.
Enhetstesterna passerade även i GitHub. Källjobben och R-kontrollen blev korrekt röda.
Grönt får kräva alla obligatoriska jämförelser. Misslyckad referens eller överhoppad kontroll ger blockerat/rött resultat.

Krav för produktionsgodkännande:

- Referensuttag = sammanslagna deluttag för alla logiska nycklar och värden; noll bortfall, extra nycklar eller ändrade värden.
- Noll dubbla logiska nycklar även när värdena skiljer sig.
- Total för ämne/studieform, kön och ålder jämförs mot UKÄ:s egna separata totaluttag. Ingen summa konstrueras.
- Varje planerad del har `verified_data` eller `verified_empty` med sparat referensbevis. Tekniska fel får aldrig bli `verified_empty`.
- Täckningsrapport anger faktiskt observerade perioder, lärosäten, kön och åldrar; filterutbud redovisas separat.
- Simulerat avbrott återupptar lyckade delar utan källanrop, spärrar korrupt cache och hanterar källrevision.
- Databastest med rollback bevisar ofullständig manifestspärr, idempotens, tappat finaliseringssvar och bevarad föregående publicering.

## 5. Publicering och återstart

Ingen merge eller produktionsimport är motiverad av dagens resultat.
Diagnostiken kan återstartas från sparade artefakter med samma explicit angivna snapshot-ID;
detta är en diagnostikkampanj och inte ett intyg om källversion för publicering.
Efter godkända käll- och databastester: driftsätt schema/endpoints, mergea verifierad kod,
publicera först en komplett indikator och läs tillbaka både rå täckning och aggregat innan nästa indikator.
Rapportera varje indikator separat och lämna en tidigare korrekt snapshot aktiv för varje blockerad indikator.

## Inventerat filterutbud

Se `uka-source-inventory-2026-11-06.json` för exakta periodlistor, antal lärosätesalternativ,
kön, åldrar och gruppstruktur. Inventeringen är inte en rapport över importerade observationer.


## Publiceringsgranskning efter utökad JSON-verifiering

Granskning av repots kod, inte en kontroll av den driftsatta databasens funktioner:

- `drizzle/migrations/0037_uka_nongeographic_storage.sql`: `uka_finalize_batch` kontrollerar
  receiving/ready samt mottagna mot klientangivna rader och chunkar. Den byter aktiv batch
  under transaktionslås. Det är ett transportsäkerhetsskydd, inte bevis för källtäckning.
- Samma funktion tar bort föregående aktiva batch vid lyckad finalisering. Behåll föregående
  korrekt snapshot tills käll- och publiceringskontrollerna är avslutade; gör därefter styrd gallring.
- `R/etl/uka_sync.R`, `uka_publish_batch`: on.exit skickar abort vid varje misslyckande.
  Även ett tillfälligt transportfel förlorar därmed möjligheten att fortsätta samma stagingbatch.
- `src/lib/uka-etl.server.ts`, `handleUkaStart`: varje start skapar nytt körnings-ID och ny batch.
  Återstart behöver en stabil importnyckel, samma manifesthash och ett progress/status-anrop;
  färdiga chunkar ska inte laddas upp igen. Fel som bryter manifestet får inte automatiskt återöppnas.
- Före byte av aktiv batch krävs hela planens färdiga hämtningar, frysta källmetadata,
  kontrollerad period/kön/ålder/lärosätestäckning, unika observationsnycklar, bevarade källtotaler
  och inga olösta tekniska tomsvar. Avslutad graf för ett urval räcker inte för en tioårssnapshot.

Dessa ändringar är ännu inte implementerade eller driftsatta. Ingen migration eller
produktionspublicering har gjorts inom diagnostiken. JSON-köerna saknar publiceringskapacitet.
