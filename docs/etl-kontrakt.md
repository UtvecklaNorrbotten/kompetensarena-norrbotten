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
4. atomisk publicering via `publish_indicator`
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
