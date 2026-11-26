# MUCF – unga som varken arbetar eller studerar

Importen avser **all publicerad UVAS-statistik i MUCF:s webbverktyg**, inte all statistik inom myndighetens övriga ämnesområden. Vid verifieringen 2026-11-25 fanns 2007–2024, riket, 21 län och 290 kommuner. År och geografier upptäcks automatiskt; MUCF:s interna geografiska ID:n översätts genom namn till SCB-koder i MUCF:s egen Ung idag-katalog. De interna ID-numren får aldrig användas som SCB-koder.

## Definition och innehåll

Detta är MUCF:s registerbaserade UVAS-mått. Det är inte identiskt med Eurostats NEET. Personer i arbetsmarknadsåtgärder kan ingå. MUCF:s avgränsning avser ett helt kalenderår och inkluderar även vissa låga arbetsinkomster. Se [källan](https://www.mucf.se/rapporter-och-statistik/statistik-om-unga-som-varken-arbetar-eller-studerar) och dess metodtext.

Importen bevarar publicerade antal och andelar för 16–24, 25–29 och 16–29 år; kvinnor, män och total; inrikes födda, utrikes födda och total, inklusive källans korsningar. Riket och länen har samtliga publicerade aktivitetskategorier; kommunerna har total och okänd aktivitet. Alla totaler hämtas direkt. Ursprung kan väljas för total UVAS men inte för aktivitetskategorier: MUCF återställer då kategorin till total, vilket importen skyddar mot genom att kontrollera svarets rubrik. Aktivitetskategorier hämtas för kön och totalt.

**Nämnaren skiljer sig:** andelen för total UVAS (`Master`) avser befolkningen i gruppen. Andelen för en aktivitetskategori avser UVAS i motsvarande grupp. `dimensions.denominator` bevarar skillnaden. Andel sparas i procent, exempelvis 6,2 som talet 6.2.

Prickar, ellipser och stjärnor ger `value: null`, `value_status: suppressed` och oförändrad `source_value`. Tomma celler får `missing`. Observerad noll förblir noll. Okända symboler, negativa tal, icke-heltal för antal och andelar utanför 0–100 avbryter importen. Ingen sekretessgräns baklängesberäknas och inga värden imputeras.

Från 2023 används CKM; delar kan skilja sig från publicerad total. Kommun- och könstotaler ska därför inte räknas fram genom summering. Från 2015 exkluderas gränspendlare till Finland, jämte Norge och Danmark. Jämförbarheten över 2014/2015 är särskilt relevant för Norrbotten. Källans tabell kan ha avvikelser även mellan åldersdelar och total: de publicerade talen behålls och tolkas med metodnoterna.

## Drift och återstart

Workflow: `.github/workflows/etl-mucf-uvas.yml`, **10 · Data · MUCF – unga utan arbete eller studier (UVAS)**. Nya fullständiga kontroller startar tidigast sju dagar efter senast färdigställd kontroll. Körluckor var sjätte timme återupptar en ofärdig insamling; när föregående kontroll är färdig och yngre än sju dagar görs inga källanrop. Hela publicerade historiken granskas på nytt, så även revideringar upptäcks. Sidans HTTP Last-Modified och ETag betraktas inte som datans publiceringstid.

Källan erbjuder ett webbformulär, inte en identifierad bulkfil. En full insamling kräver många små uttag (2024: 2 136 kombinationer; 18 år cirka 38 448, plus katalogfrågor). Första hämtningen och revisionskontroller tar därför flera körningar. Två arbetstrådar, gemensam begränsning till högst en anropsstart per sekund, nätverksåterförsök och 290 minuters körbudget skyddar både källan och GitHub-jobbet. Senaste året och Norrbotten prioriteras.

Allt sparas beständigt i samma repos separata gren **`data/mucf-uvas`**, under `data/mucf-uvas/`:

| Fil | Innehåll |
|---|---|
| `state.json` | Pågående insamlingsomgång, år, framsteg, fel och färdigställda år |
| `pending/<år>-plan.json` | Upptäckta geografier och källans kategorier |
| `pending/<år>-results.json.gz` | Godkända uttag, källtabellernas HTML, kontrollsummor och hämtningstid |
| `snapshots/<år>.json.gz` | Fullständigt validerad årgång, originalvärden, status, metodnoter och innehållshash |
| `catalog.json` | Tillgängliga år, aktiva årssnapshots och täckningsstatus |
| `published.json` | Senast publicerad innehållshash per år och mått |

Återstart läser den beständiga grenen, inte en tillfällig Actions-cache. Kontrollpunkter skrivs efter åtta uttag. Även vid fel sparas godkända uttag. En process som tvångsavslutas före sparsteget kan behöva hämta om den senaste körningens uttag; föregående sparade kontrollpunkt och aktiva årgångar finns kvar. Git push-fel markeras som workflowfel och får inte döljas.

En årgång ersätter sin tidigare snapshot först när alla förväntade uttag, geografier, mått och delgrupper har verifierats. Felaktigt urval, saknade rader och dubbletter stoppas. Hämtningen saknar en källgemensam versionsmarkör: ett års uttag kan därför ligga på olika klockslag. Första och sista hämtningstid sparas; en samtidighetsgaranti om MUCF reviderar mitt under uttaget kan inte ges.

## Databas och publicering

`0058_mucf_uvas_registration.sql` registrerar endast två indikatorer och en datakälla; inga nya tabeller eller funktioner krävs. Registreringen ska vara applicerad innan första databaspubliceringen. `ETL_BASE_URL` och `ETL_PUBLISH_KEY` återanvänds från befintliga Actions-hemligheter.

- `mucf-uvas-antal` – personer.
- `mucf-uvas-andel` – procent.
- Datakälla: `mucf-uvas`, kontrollfrekvens `weekly`.

`scripts/mucf/publish.py` använder befintlig `etl-batch/start` → `chunk` → `finalize` med `replace_period`. Vid första publiceringen skapas indikatorns historik med en full batch, eftersom en periodbatch kräver en aktiv bas. Därefter används periodbatchar. Befintlig historik avgörs via serverns ETL-status, inte av en lokal kontrollpunkt. Redan färdiga år publiceras före fortsatt insamling. Varje år och indikator publiceras atomiskt. Antal och andel är två separata batchar; de har inte en gemensam transaktion. Slutstatus sätts till lyckad först när båda måtten och samtliga år är färdiga. Innehållshash hindrar onödiga ompubliceringar. Ofärdiga år ändrar inte tidigare publicerade observationer. Källans uppdateringsdatum lämnas tomt; hämtningstid får inte skickas som publiceringsdatum.

Källstatus visas via `data_source_state` och `data_source_runs` enligt projektets befintliga kontrakt. Någon ny användarsida eller generell aggregering av överlappande kategorier ingår inte. Framtida visualiseringar ska läsa förberedda aggregat, med explicit val av nämnare och kategori.

## Lokal kontroll

```sh
python -m pip install -r scripts/mucf/requirements.txt
python -m unittest discover -s tests -p test_mucf_uvas.py -v
PYTHONPATH=scripts python -m mucf.collect --root /tmp/mucf-check --sample --budget-minutes 5
```

Provläget kontrollerar den senaste årgångens geografikatalog och hämtar högst åtta riktiga urval; det får aldrig markera en hel årgång eller historiken som färdig. Full insamling görs utan `--sample`. Tester använder även en verklig källtabell för Norrbotten, 2024, hämtad 2026-11-25.
