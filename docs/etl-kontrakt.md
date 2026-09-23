# ETL-kontrakt

Detta dokument beskriver kontraktet mellan R-baserade ETL-jobb och webbplattformen.

## Flöde

GitHub Actions kör R-skripten. R ansvarar för:

1. kontroll av källans metadata
2. hämtning av data vid behov
3. transformation till plattformens gemensamma format
4. teknisk validering
5. anrop till plattformens ETL-endpoint

Webbplattformen ansvarar för:

1. autentisering av ETL-anrop
2. strikt validering av payload
3. kontroll att indikatorn finns
4. atomisk publicering via `publish_indicator` för små dataset eller det versionerade batchflödet för stora dataset
5. uppdatering av metadata och körningslogg

## Säkerhet

- ETL-hemligheten ska finnas som GitHub Actions Secret och Lovable secret.
- Hemligheten får aldrig loggas eller skickas till klienten.
- Endpointen ska inte ge generell databas- eller adminåtkomst.
- Okänd indikator ska avvisas.
- Ogiltig payload ska avvisas innan publicering.
- Misslyckad publicering ska lämna tidigare data oförändrad.

## Metadata

Följande begrepp är styrande:

| Fält | Betydelse |
| --- | --- |
| `kalla_uppdaterad_datum` | Datum då källan publicerade eller uppdaterade data |
| `hamtad_datum` | Datum då Kompetensarena hämtade data |
| `tillganglighetsdatum` | `coalesce(kalla_uppdaterad_datum, hamtad_datum)` |
| `styrande_kalla` | Källa som styr indikatorns uppdatering |

## Körningsstatus

`data_source_runs` använder minst:

- `started`
- `no_change`
- `succeeded`
- `failed`

Vid `failed` ska ett användbart felmeddelande loggas, men aldrig hemligheter eller autentiseringsuppgifter.

## Idempotens

Samma validerade dataset ska kunna skickas igen utan att skapa dubbletter eller ett annat sluttillstånd.

Publicering ska vara knuten till en specifik indikator och får inte påverka andra indikatorer.

## Framtida datakällor

Kontraktet ska vara källoberoende. SCB är första användningsfallet, men samma endpoint/publiceringsmönster ska kunna användas av Kolada, Trafikanalys och andra betrodda källor.


## SCB/PxWeb2

SCB-indikatorer använder ett gemensamt lager i `R/etl/scb_common.R` och ett gemensamt GitHub Actions-workflow.

Gemensamt ansvar:

1. kontrollera senaste lyckade ETL-publicering mot SCB:s fulla `updated`-timestamp med `pxweb2_table_needs_update()`
2. logga `no_change` utan datahämtning när tabellen inte är nyare
3. hämta och återanvända PxWeb2-metadata när ny data behövs
4. återanvända säkra hjälpfunktioner för kodlistor och cellgränser
5. publicera genom samma källoberoende ETL-klient

Indikatorspecifikt ansvar ska ligga kvar i respektive skript: query, dimensionsurval, transformation och teknisk validering. Det minskar risken att en generell funktion råkar anta samma tabellstruktur för olika SCB-indikatorer.


## Gemensamt källregister och senaste lyckade hämtning

Indikatorstatus och källstatus är två olika saker. En källa kan försörja flera indikatorer
och vissa kontroller, som Arbetsförmedlingens fem månadsfiler, sker innan någon enskild
indikator publiceras.

Därför finns ett generellt lager:

- `data_sources`: en rad per logisk källa eller källpaket.
- `data_source_state`: aktuellt läge för källan.
- `data_source_runs.source_id`: kopplar körningshistorik till samma källa.

`data_source_state` håller minst:

- `latest_available_period`
- `latest_successful_period`
- `last_checked_at`
- `last_successful_at`
- `last_status`
- `last_error`
- `details`

Det gör att en administrativ statussida senare kan svara på två separata frågor:
**vad finns senast hos källan?** och **vad lyckades Kompetensarena senast hämta/publicera?**

Första registrerade källor är `scb-tab6929` och `af-monthly`.
