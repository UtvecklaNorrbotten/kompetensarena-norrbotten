# UKÄ: genomströmning och regional uppföljning

Verifierat mot officiella källor 29 oktober 2026. Utökningen använder `scripts/uka_extended_sync.py`; de sju ursprungliga indikatorerna använder oförändrat `R/etl/uka_sync.R`.

## Källor och importer

| Kompetensarenas indikator | UKÄ-källa | Perioder i kontrollerat uttag | Rader |
|---|---|---|---:|
| `uka-examensfrekvens` | Högskolan i siffror 135 | nybörjarläsår 2007/08–2021/22 | 78 213 |
| `uka-kvarvaro-program` | Högskolan i siffror 134 | nybörjarläsår 2007/08–2023/24 | 93 558 |
| `uka-kvarvaro-hogskolenyborjare` | Högskolan i siffror 77 | nybörjarläsår 2000/01–2023/24 | 3 552 |
| `uka-prestationsgrad` | UF0208, SCB:s reviderade tabell 4 | registreringsläsår 2014/15–2023/24 | 6 990 |
| `uka-regional-examinerade` | UF0205, regional tabell | examensläsår 2012/13–2023/24 | 318 |
| `uka-regional-rekryterade-antal` | samma regionala tabell | samma examensårskullar | 318 |
| `uka-regional-bosatta-antal` | samma regionala tabell | samma examensårskullar | 318 |
| `uka-regional-rekryterade-andel` | samma regionala tabell | samma examensårskullar | 317 |
| `uka-regional-bosatta-andel` | samma regionala tabell | samma examensårskullar | 318 |

Totalt 183 902 observationer i källkontrollen. API-indikatorerna omfattar alla lärosäten i källans historik (inklusive historiska lärosätesnamn), Riket, kvinnor/män/total och åldersgrupper. 134/135 bevarar program. Prestationsgrad omfattar 40 lärosätes-/totaletiketter i källan, kön, program/kurs och campus/distans där källan redovisar dessa. 674 celler är inte tillgängliga eller kan inte förekomma och lagras som null, aldrig som noll. Tabellen skiljer mellan yrkesexamensprogram, generella program och fristående kurser; den ger inte prestationsgrad för varje enskilt yrkesprogram.

UKÄ:s API returnerar olika senaste nybörjarår för olika program. Slutåret 2021/22 betyder alltså inte att civilingenjörs- eller sjuksköterskekullen 2021/22 redan kan följas upp.

### Exakta adresser

- [UKÄ:s statistiska meddelanden och aktuella bilagor](https://www.uka.se/statistik-och-analys/om-var-statistik/statistiska-meddelanden).
- [Definitioner: utbildning på grundnivå och avancerad nivå](https://www.uka.se/statistik-och-analys/hogskolan-i-siffror/beskrivningar-av-statistiken/utbildning-pa-grundniva-och-avancerad-niva).
- Metadata: `https://statistik-api.uka.se/api/totals/135/`, motsvarande `/134/` och `/77/`.
- CSV-export: `https://statistik-www.uka.se/export/api/index.php`, med officiella filter från `/export/filters/`. POST med `indicator` och `filters[]` ger `fileUrl`.
- [UF0208: senaste reviderade tabeller](https://www.scb.se/uf0208). Importen hittar länken med rubriken **Prestationsgrad efter kön, lärosäte och program/kurs** och använder den aktuella Excel-filen. Den verifierade utgåvan publicerades 21 maj 2026. UKÄ:s SM-bilaga har kortare tidsserie och används därför inte för detta mått.
- [Aktuell prestationsgradstabell](https://www.scb.se/hitta-statistik/statistik-efter-amne/utbildning-samt-forskning-inom-hogskolan/hogskolevasende/genomstromning-och-resultat-i-hogskoleutbildning-pa-grundniva-och-avancerad-niva/pong/tabell-och-diagram/prestationsgrad-efter-kon-larosate-och-programkurs-lasaren-201415202324/).
- [UF0205 2024/25, rapport inklusive tabell 34, sida 54](https://www.uka.se/download/18.56a811e519d6b4ded4eec7/1775642375876/UF0205_2024L25_SM_UF20SM2601-Studenter%20och%20examinerade.pdf).
- [SCB:s UF0205-arkiv](https://www.scb.se/uf0205). Äldre verifierade rapportadresser finns i `config/uka_regional_sources.json`.

## Populationer och tolkning

**Examensfrekvens (135):** avsedd examen inom programmets nominella studietid plus tre år. Perioden är nybörjarår, inte examensår. Lärosätesvärdet kräver examen vid samma lärosäte som vid programstart; riksvärdet tillåter examen vid annat lärosäte. Korta kompletterande lärarutbildningar, exempelvis KPU med högst 150 hp, ingår inte i grundlärar-, ämneslärar- och förskollärarprogrammens mått enligt UKÄ.

**Kvarvaro (134):** registrerad på samma program termin tre, och för lärosätesvärdet även samma lärosäte. Riksvärdet tillåter byte av lärosäte inom samma program. Korta 60 hp-program ingår inte. 77 avser i stället högskolenybörjare kvar vid samma lärosäte. Måtten inkluderar inresande studenter. De är inte statistik över permanent studieavbrott. Därför skapas ingen indikator genom att beräkna `100 − kvarvaro` och kalla resultatet studieavbrott.

**Prestationsgrad:** avklarade poäng på de kurser studenten registrerades på under registreringsterminen och tre efterföljande terminer, dividerat med registreringspoäng. Den individkopplingen kan inte återskapas korrekt genom att dividera fristående HPR och HST för samma år. Prestationsgrad hämtas därför direkt från den officiella tabellen.

**Regional uppföljning:** populationen är examinerade ett visst läsår. Rekryteringslän avser folkbokföringen året före högskolestart; bosättning avser det angivna datumet omkring två år efter examen. För examensår 2023/24 är datumet 2025-12-31. Samma examensårskull används i båda måtten; rekryterade är inte det aktuella årets nybörjare. Antal och procent läses separat från källans fem sifferkolumner. Källans avrundade antal bevaras som publicerade och beskrivs inte som exakta individantal.

Tabell 34 finns i PDF-rapporten; den aktuella Excelbilagan har andra tabeller och saknar tabell 34. PDF-kolumnerna identifieras geometriskt och kontrolleras för rimliga antal, procent och fullständig LTU-rad. Ny layout eller misslyckad historikläsning stoppar publicering av den regionala snapshoten. Detta är en mer känslig distributionsform än CSV/Excel och kräver fortsatt källkontroll.

Den regionala tabellen omfattar lärosäten med minst 500 examinerade och utesluter SLU, som är spritt över flera län. Källan stödjer alltså inte regional uppföljning för samtliga svenska lärosäten. Historiken innehåller 33 olika lärosätesnamn, inklusive namnbyten; de får inte räknas som 33 samtidiga lärosäten. Kön och enskilt utbildningsprogram saknas i just denna regionala tabell. Högskolelän är inte samma sak som kursort och bosättning är inte arbetsplats.

### Spärrade uppgifter i senaste regionala källan

- Mälardalens högskola och Mittuniversitetet: fotnotsnumren kopplar lärosätena till ombytta län. De båda raderna för examensår 2022/23 och 2023/24 publiceras inte; tidigare verifierade år behålls. Kontrollen använder fotnoternas innehåll och släpper in uppgifterna när källan rättats.
- Handelshögskolan i Stockholm: tabellen anger 45 procent rekryterade, löptexten anger 35 procent. Andelen för 2023/24 spärras. De separat publicerade antalen och bosättningsandelen behålls.
- Ingen egen korrigering eller uppskattning införs. Spärrarna loggas i varje fullständig källkontroll.

## Arbetsplats i samma län efter examen

Den efterfrågade statistiken finns i [UKÄ rapport 2023:20, Etablering på arbetsmarknaden efter studier i högskolan](https://www.uka.se/download/18.44865ea18c38c0aae968cbd/1702975618181/Rapport%20Etablering%20p%C3%A5%20arbetsmarknaden%20efter%20studier%20i%20h%C3%B6gskolan.pdf), särskilt sidorna 49–54 och figur 14 på sida 54 (PDF-sida 54).

Den visar andelen av **de etablerade**, examinerade 2019/20, som arbetade i lärosätets hemlän ett år efter examen (2021). Arbetsregionen är arbetsställets län. Figur 14 omfattar de 16 lärosätena med flest examinerade; figur 12 avser 18 yrkesexamina och figur 13 könsuppdelning för tio examina. Bilaga 5 beskriver hemlänen; fyra lärosäten kan ha två hemlän och SLU utesluts. Rapporten skiljer inte campus från distans.

Denna statistik är inte indikator 136, som mäter andelen etablerade bland den relevanta examinerade populationen. Jag har inte verifierat ett komplett, återkommande maskinläsbart underlag till regionfigurerna. Stapellängder har inte mätts och inga osäkra procent har importerats. Nästa steg för en sådan import är ett officiellt tabellunderlag från UKÄ, med arbetslän, lärosäte, program, kön och uppföljningsår samt deras publiceringsrutin.


### Fördjupad kontroll av arbetsregion, 30 oktober 2026

Status: **inväntar verifierat tabellunderlag från UKÄ**. Ingen ny arbetsregionsindikator eller ETL-publicering har skapats. Det är en källbegränsning, inte en misslyckad GitHub-körning.

Följande officiella underlag kontrollerades direkt:

| Underlag | Kontroll | Resultat för arbetsregion |
|---|---|---|
| [Excelbilaga till rapport 2023:20](https://www.uka.se/download/18.1952a0b618cc6c4f1ac56ae/1704200289857/Etablering%202019-20%20Webbtabeller.xlsx), examinerade 2019/20 | Arbetsbokens blad och celltexter, inklusive innehållsförteckningen | Tabeller 1–5 avser arbetsmarknadsställning, sektor och etableringsgrad. Inget tabellunderlag till rapportens regionala figurer 12–14 hittades. |
| [Excelbilaga publicerad 2025](https://www.uka.se/download/18.6d376bec1969f608fca4c/1747312467366/Tabellbilaga-etablering%20p%C3%A5%20arbetsmarknaden.xlsx), examinerade 2021/22 | Tabellrubriker och celltexter samt inbäddade objekt/pivotunderlag | Inget arbetsregionsunderlag hittades. |
| [Excelbilaga publicerad 2026](https://www.uka.se/download/18.44ee87e019e634696534/1779784405696/Tabeller%20Etablering%20p%C3%A5%20arbetsmarknaden%20efter%20studier%20i%20h%C3%B6gskolan%20-%20Examinerade%20p%C3%A5%20grundniv%C3%A5%20och%20avancerad%20niv%C3%A5%202022-23.xlsx), examinerade 2022/23 | Blad, celltexter och pivotunderlag | Tabell 4a–c har kolumnen ”Andel i region (%)”. Den avser arbetsgivarsektor, tillsammans med näringsliv, kommun och stat. Den mäter inte arbete i lärosätets län. |
| [Högskolan i siffrors export](https://statistik-www.uka.se/export/), indikator 136 | Indikatorförteckningen och `/export/filters/group.php?indicator=%5B%22136%22%5D` | Ingen separat arbetsregionsindikator identifierades. Gruppfiltret för 136 redovisar examen, inte arbetslän. |
| Rapport 2023:20, PDF-sidor 50–54 | Text, bilagor inbäddade i PDF-filen och länkar vid de regionala figurerna | Inga inbäddade datafiler eller länkar till ett numeriskt tabellunderlag hittades. Figurerna har inte omvandlats till uppskattade procenttal. |

Kontrollen bevisar inte att UKÄ saknar ett separat underlag eller en senare specialpublicering. Den visar att de granskade standardbilagorna och exporten inte gav ett verifierat underlag för denna import.

**Ytterligare definitionsvillkor:** Rapportens arbetsregion avser huvudsakligt arbetsställes län under uppföljningsåret. Om arbetsställe saknas används bostadslän som reserv. För vissa kommunanställda med okänt eller växlande arbetsställe används arbetsgivarkommunens län. Ett sådant värde ska därför inte beskrivas som en alltid direkt observerad fysisk arbetsplats. Hemlän kan dessutom bestå av två län, och distansstudenter skiljs inte ut. Dessa villkor måste följa med en eventuell indikator.

#### Underlag att begära från UKÄ

Begär i första hand det officiella numeriska figurunderlaget till figurerna 12–14 i rapport 2023:20, särskilt figur 14 för lärosäten. Be också om senare årgångar och besked om uppgifterna uppdateras återkommande. Om UKÄ kan lämna ett mer detaljerat uttag behövs:

- examensläsår och uppföljningsår, samt uppföljningstid efter examen;
- lärosäteskod/-namn och definition av dess hemlän, inklusive lärosäten med flera hemlän;
- antal etablerade i nämnaren, antal med arbetsregion i hemlänet och publicerad andel;
- arbetslän, examen/program och kön där dessa kombinationer faktiskt finns publicerade;
- sekretessmarkeringar, avrundningsregler, bortfall och hantering av saknat arbetsställe;
- filformat, versionsdatum och stabil publiceringsadress/API eller annan uppdateringsrutin.

Kravet på alla dessa dimensioner gäller ett eventuellt detaljerat uttag. Det hindrar inte en tydligt avgränsad import av det officiella figurunderlaget om endast lärosätesandelar finns tillgängliga. En engångstabell kan lagras som historiskt underlag men får inte presenteras som en årligen uppdaterad serie.

Ingen kontakt med UKÄ har skickats inom denna kontroll. Nästa externa beroende är att få underlaget eller ett besked om var det publiceras.

## Drift, revideringar och lagring

- Workflow: `10 · Data · UKÄ – högskolan i siffror`, `.github/workflows/etl-uka.yml`. Den nya delen kan väljas manuellt med `indicator=extended`, eller inkluderas med `all`. `test_mode=true` publicerar ingenting.
- Veckovis kontroll av API-metadata och HTTP `Last-Modified`/ETag för filkällorna före full export. Om markörerna inte ändrats sker ingen dataexport eller batchpublicering. Full hämtning görs vid första veckokontrollen i ett nytt kalenderkvartal för historiska revideringar som inte syns i aktuell API-total.
- API:t exponerar inget verifierbart uppdateringsdatum i totalsmetadata. För dessa importer lämnas `kalla_uppdaterad_datum` tomt, i stället för att felaktigt använda dagens datum. Hämtdatum sätts av befintlig finalisering. Filkällors tillgängliga uppdateringsmarkörer sparas i körningsrapporten. För den regionala snapshoten används det senaste Last-Modified-datumet bland de ingående rapporterna (verifierat 2026-04-08); för prestationsgraden är filens datum 2026-05-19, medan publiceringssidan anger 2026-05-21.
- De nya indikatorerna behåller hela den verifierade historiken. De sju ursprungliga indikatorernas avsiktliga femårsregel och urval av aktiva lärosäten ändras inte.
- Publicering använder befintliga `/api/public/jobs/uka/start`, `chunk`, `finalize`, `abort`, `uka_batches`, `uka_active_batches`, `uka_observations` och `agg_uka_university`. Varje indikator aktiveras atomiskt efter fullständig laddning. Befintlig versionshantering ersätter föregående aktiva snapshot utan identiska parallella datakopior.
- Indikatorregistrering: `drizzle/migrations/0045_uka_completion_regional.sql`. Migrationen har applicerats i ansluten databas.
- Separat källstatus: `uka-genomstromning-regional`. Detaljer innehåller fingeravtryck, källadresser, antal, perioder, LTU-exempel och spärrar. Rapporten sparas också som Actions-artifact `uka-genomstromning-regional` i 90 dagar.
- Det tidigare `uka-regional-audit.yml` och dess låsta granskningsskript har ersatts av integrerade kontroller, inte ytterligare ett schemalagt workflow.
- Test: `python -m unittest discover -s tests -p test_uka_extended.py -v`. Fullständig reproducerbar källkontroll utan publicering: `python scripts/uka_extended_sync.py`. Lokala hämtade källfiler kan kontrolleras med `--cache` och får inte publiceras.

## Jämförelse som går att göra

Samtliga kön, samtliga åldrar, samma program och nybörjarår:

| Mått | Program | Nybörjarår | LTU | Umeå universitet |
|---|---|---|---:|---:|
| Examensfrekvens, avsedd examen | Sjuksköterskeexamen | 2019/20 | 57,7 % | 66,8 % |
| Examensfrekvens, avsedd examen | Civilingenjörsexamen | 2017/18 | 38,8 % | 53,8 % |
| Examensfrekvens, avsedd examen | Grundlärarexamen | 2018/19 | 58,1 % | 61,9 % |
| Kvarvaro på program termin 3 | Sjuksköterskeexamen | 2023/24 | 76,4 % | 63,6 % |

Låg examensfrekvens bevisar inte svag undervisningskvalitet. Skillnader i studenturval, studieupplägg, övergång till andra lärosäten eller arbete utan uttagen examen kan påverka utfallet. Kvarvaro och examensfrekvens i tabellen avser olika nybörjarkullar och får inte användas som två steg i samma kulls utveckling.

## Rekommendationer som inte implementerats

Kontrollerade via UKÄ:s metadata och periodfilter 29 oktober 2026. Samtliga API-poster nedan distribueras som CSV via samma exporttjänst som ovan. De saknas bland dagens importerade UKÄ-indikatorer, och inga motsvarande separata högskoleindikatorer hittades i Kompetensarenas indikatorkatalog. Mikrodata i MONA kan överlappa på individnivå, men är inte samma publika aggregerade import.

| Prioritet / källa | Vad statistiken mäter och dimensioner | Tillgänglig historik | Överlapp och nytta |
|---|---|---|---|
| Hög: 27/28 | Högskolenybörjare respektive nybörjare vid ett visst lärosäte; lärosäte, rekryteringslän/kommun, kön och ålder | HT1993–VT2026 | Inte samma population som regionala examinerade. Visar upptagningsområde och bredd i rekryteringen; kan komplettera MONA. Kommunfilter behöver kontrolleras före en komplett export. |
| Hög: 95/98/101 | Förstahandssökande, antagna och söktryck för generella program; lärosäte, SUN-inriktning, studieform, kön och ålder där det finns | HT2007–HT2026 | Nuvarande 13/97/99 omfattar yrkesexamensprogram, inte dessa program. Relevant för utbildningsdimensionering. |
| Hög: 26 | Registrerade på yrkesexamensprogram; lärosäte, program, kön och ålder | VT1997–VT2026 | Nybörjare (31) och HST (33) mäter annat. Ger studentvolymen under utbildning. |
| Hög: 35 | HST per yrkesexamensprogram; lärosäte, program, kön och ålder | 2007/08–2025/26 i exportens periodfilter | Delvis samma total som 33, men programdimensionen tillför information. Undvik separata kopior av identiska totaler. |
| Medel: 119 | Registrerade individer per ämnesgrupp; lärosäte, ämnesområde/-grupper, kön och ålder | 1977/78–2025/26 | Individer är inte HST. Kan belysa utbildningsvolym och kompetensutveckling. |
| Medel: 81/85 | Återkommande efter examen respektive efter minst tre terminers frånvaro; lärosäte och kön | HT2001–HT2025 | Saknas i dagens import. Relevant för livslångt lärande; definitionerna kräver separat redovisning. |
| Medel: 138/141 | Doktorandnybörjare och doktorsexamina; lärosäte, forskningsämne, kön och ålder | 1973–2025 | Saknas. Relevant för forskarutbildad kompetens. Nya API-ID ersätter äldre serier; klassifikationsbyten behöver beaktas. |
| Medel: 54/56 | Personal som individer respektive forskande/undervisande heltidsekvivalenter; lärosäte, anställningskategori, kön, ålder och forskningsämne där det finns | 2001–2025 | Saknas som högskoleimport. Befintlig sysselsättningsstatistik kan överlappa personer men beskriver inte samma anställningsstruktur eller utbildningskapacitet. |
| Utred: poänggivande uppdragsutbildning | Officiell Excel på UKÄ:s utbildningssida; uppdragsutbildning vid lärosäten | Historik/dimensioner ännu inte verifierade | Kan visa arbetsgivares kompetensutveckling. Ingen import innan tabellstruktur och överlapp har granskats. |
| Utred: arbetsplats i hemlänet | UKÄ 2023:20, figurer 12–14 | Verifierad analys av examensår 2019/20, uppföljning 2021 | Regional kompetensförsörjning; kräver verifierat tabellunderlag innan automation. |

Statistik om svensk och utländsk bakgrund har inte valts ut eller implementerats.
