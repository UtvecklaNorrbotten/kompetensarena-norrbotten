# Utveckla vidare från GitHub

Kompetensarena Norrbotten byggs i Lovable, men koden är vanlig React/Vite och kan klonas, byggas och vidareutvecklas direkt från GitHub.

## Kom igång lokalt

```bash
# 1. Klona repositoryt (byt ut URL:en mot det riktiga)
git clone https://github.com/<organisation>/kompetensarena-norrbotten.git
cd kompetensarena-norrbotten

# 2. Installera beroenden
bun install
# alternativt: npm install

# 3. Starta utvecklingsserver
bun run dev
# öppna http://localhost:8080
```

> Projektet använder Lovable Cloud/Postgres för indikatorer och metadata. Lokal utveckling av databasanslutna sidor kräver motsvarande Supabase/Lovable-miljövariabler. Externa statistik-API:er anropas däremot aldrig vid sidladdning.

## Filstruktur

```text
src/
  routes/          sidor: /, /om, /statistik, /kommer-senare
  components/
    layout/        Header, DesktopNav, MobileNav, Footer, Logo, Section, AppLink
    ui/            PageHeader, MetadataList, ExampleBadge
    charts/        TimeSeriesChart, IndicatorPanel
  config/          navigation.ts (meny), site.ts (namn, kontakt)
  data/            delade typer för indikatorer och tidsserier
  lib/             datalager (indicators.ts) + serverfunktioner (indicators.functions.ts)
  assets/          logotyp, ikoner, illustrationer, figurer, bilder
  styles.css       designsystem: färger, typografi, spacing, radier, states
```

## Viktiga konventioner

1. **Designsystem i en fil.** Alla färger, radier, spacing och typografi finns i `src/styles.css`. Hårdkoda aldrig hex-värden i komponenter — använd klasser som `bg-brand-light`, `text-brand-dark`, `text-ink-muted`.
2. **Menyn är konfiguration.** Alla menytexter och länkar ligger i `src/config/navigation.ts`. Komponenterna läser den filen.
3. **Data via tunt lager.** Komponenter hämtar inte data själva. Använd `listIndicators()` / `getIndicator(id)` från `src/lib/indicators.ts`. När riktiga datakällor tillkommer byts implementationen där.
4. **Logotyp som asset.** Huvudlogotypen använder den uppladdade vita Utveckla Norrbotten-logotypen via Lovables asset-lagring. Övrig profilgrafik hålls samlad under `src/assets/`.
5. **Inga stora monolitiska komponenter.** Dela upp i små, namngivna komponenter som beskrivs i `docs/komponenter.md`.

## GitHub-arbetsflöde

Lovable har tvåvägs-synk med GitHub:

- Ändringar du gör i Lovable pushas automatiskt till GitHub.
- Ändringar du pushar till GitHub synkas tillbaka till Lovable.
- Du kan arbeta i grenar, öppna pull requests och granska ändringar i GitHub precis som i vanligt utvecklingsarbete.

### Förslag på arbetssätt

1. **Gör större ändringar i en gren**, t.ex. `feature/nya-menyn`.
2. **Öppna pull request** i GitHub för granskning.
3. **Mergea till huvudgrenen** när ändringen är klar.
4. **Låt Lovable synka** tillbaka huvudgrenen automatiskt.

### Filer som inte ska ändras för hand

- `src/routeTree.gen.ts` genereras automatiskt av TanStack Router. Ändra den aldrig manuellt.
- `routeTree.gen.ts` finns i `.prettierignore` för att undvika konflikter.

## Nästa utvecklingssteg

1. Bygg statussida för datauppdateringar och metadata.
2. Lägg till nästa verifierade SCB-indikator i det gemensamma ETL-registret.
3. Förbered motsvarande källadapter för Kolada/Trafikanalys när första sådana indikator väljs.
4. Fastställ informationsarkitektur och byt ut kvarvarande placeholder-innehåll.
5. Bygg inloggning och roller, därefter dokumentuppladdning.
6. AI-chatt med källhänvisning — efter separat genomgång av kostnad, GDPR och förvaltning.

## ETL-endpoint: publicering av indikatordata

`POST /api/public/jobs/publish-indicator`

- **Autentisering:** `Authorization: Bearer <ETL_PUBLISH_KEY>`. Nyckeln lagras som
  hemlighet i Lovable och i GitHub Actions Secrets — aldrig i repot, aldrig i frontend
  och den loggas aldrig. Vid nyckelbyte kan `ETL_PUBLISH_KEY_PREVIOUS` sättas tillfälligt.
- **Payload (strikt validerad med zod):**

```json
{
  "indicator_id": "exempel-arbetsloshet",
  "source": "SCB",
  "kalla_uppdaterad_datum": "2026-09-01",
  "observations": [{ "geo_code": "25", "period": "2020", "value": 7.9, "dimensions": {} }]
}
```

- **Svarskoder:** 200 lyckad publicering, 400 felaktig payload, 401 saknad nyckel,
  403 fel nyckel, 404 okänd indikator, 413 för stor payload, 422 publicering avvisad av
  databasen, 429 för många anrop.
- **Begränsningar:** endpointen kan bara anropa `publish_indicator` för angiven indikator.
  Ingen generell databasåtkomst och inga adminfunktioner exponeras. Publiceringen är
  atomisk — misslyckas något ligger befintlig data kvar orörd.
- **Loggning:** varje anrop skrivs till `data_source_runs` (`started` →
  `succeeded`/`failed` med radantal och felmeddelande). Hemligheten loggas aldrig.
- **Takbegränsning:** max 12 anrop per minut och serverinstans; samtidiga publiceringar av
  samma indikator serialiseras dessutom av advisory lock i databasfunktionen.

## ETL-endpoint: chunkad publicering av stora indikatorer

För dataset som överstiger gränsen för `publish-indicator` (50 000 observationer / ~2 MB)
finns ett chunkat flöde med staging och atomisk finalisering. Den enkla endpointen ovan
finns kvar oförändrad för mindre dataset.

Samma autentisering gäller för alla steg: `Authorization: Bearer <ETL_PUBLISH_KEY>`.
Nyckeln finns bara som hemlighet i Lovable och GitHub Actions Secrets — aldrig i repot,
aldrig i frontend, aldrig i databasen och den loggas aldrig.

### Flöde

```text
start  ->  chunk 0..n-1  ->  finalize
                 |
                 +-- vid fel: abort
```

1. `POST /api/public/jobs/etl-batch/start`

```json
{
  "indicator_id": "e3-matchning-utbildning",
  "source": "SCB",
  "expected_chunks": 12,
  "expected_rows": 184320,
  "kalla_uppdaterad_datum": "2026-09-18"
}
```

Svar: `{ "batch_id": "...", "status": "started", ... }`. En rad skapas i
`data_source_runs` med status `started`.

2. `POST /api/public/jobs/etl-batch/chunk` (en gång per chunk)

```json
{
  "batch_id": "...",
  "indicator_id": "e3-matchning-utbildning",
  "chunk_index": 0,
  "observations": [{ "geo_code": "25", "period": "2023", "value": 12.4, "dimensions": {} }]
}
```

Svar: mottaget antal chunkar/rader samt batchens status (`receiving` eller `ready`).
Chunkar kan skickas i valfri ordning. En identisk chunk som skickas igen är idempotent
(`"duplicate": true`); samma index med annat innehåll avvisas.

3. `POST /api/public/jobs/etl-batch/finalize` med `{ "batch_id": "..." }`

Publicerar hela batchen atomiskt och markerar batchen `succeeded`.

4. `POST /api/public/jobs/etl-batch/abort` med `{ "batch_id": "...", "reason": "..." }`

Rensar stagingdata, markerar batchen `failed` och loggar körningen som misslyckad.

### Atomisk finalisering

Finaliseringen sker helt i databasfunktionen `etl_finalize_batch`, i en enda transaktion:
kontroll att alla chunkar finns och att radantalet stämmer, advisory lock per indikator,
ersättning av indikatorns observationer, uppdatering av `indicator_metadata` (RUS-fält),
körningslogg i `data_source_runs` och rensning av stagingchunkarna. Misslyckas något steg
rullas allt tillbaka och tidigare publicerad data ligger kvar oförändrad.

### Statuskoder

| Kod | Betydelse |
| --- | --- |
| 200 | Steget lyckades |
| 400 | Ogiltig payload (zod) eller ogiltig JSON |
| 401 | Saknad nyckel |
| 403 | Fel nyckel |
| 404 | Okänd indikator eller okänd batch |
| 409 | Fel tillstånd: dubblerad chunk med annat innehåll, chunk för fel indikator, `chunk_index` utanför intervallet, finalisering innan alla chunkar mottagits, felaktigt radantal |
| 413 | För stor request body |
| 422 | Publicering avvisad av databasen (t.ex. okänd geografi) |
| 429 | För många anrop |

### Begränsningar

- Max 20 000 observationer och ~6 MB per chunk-anrop.
- Max 1 000 chunkar per batch.
- Takbegränsning: 240 chunk-anrop respektive 30 start/finalize/abort-anrop per minut och
  serverinstans.
- Stagingtabellerna (`etl_batches`, `etl_batch_chunks`) är inte läsbara för frontend eller
  inloggade användare — inga rättigheter utöver serverns, RLS på utan policies.
- Städning av övergivna batcher sker med databasfunktionen `etl_cleanup_batches(interval)`
  (standard 48 timmar). Inget schemalagt jobb är kopplat ännu.


## GitHub Actions för SCB-indikatorer

SCB-flödet är generaliserat men innehåller tills vidare bara den verifierade indikatorn E3:

- `R/etl/run_scb.R` — gemensam entrypoint.
- `R/etl/scb_indicators.R` — register över tillåtna SCB-indikatorer och deras skript.
- `R/etl/scb_common.R` — gemensam metadata-kontroll, kodlistor, SCB-celluppdelning och standardisering.
- `R/etl/e3_tab6929.R` — E3-specifik query, transformation och validering.
- `R/etl/etl_api.R` — källoberoende klient för ETL-endpoints och chunkad publicering.
- `.github/workflows/etl-scb-indicators.yml` — gemensamt SCB-workflow. E3 körs dagligen cirka 05:00 svensk tid och kan även köras manuellt.

Att lägga till en ny SCB-indikator ska normalt innebära ett eget verifierat indikator-skript plus en post i `scb_indicators.R`, inte ett duplicerat workflow.

Följande GitHub Actions Secrets måste sättas innan workflowet kan köras:

- `ETL_BASE_URL` — webbplatsens publika basadress, utan avslutande snedstreck.
- `ETL_PUBLISH_KEY` — samma ETL-nyckel som finns som Lovable-secret.

SCB kräver ingen API-nyckel.

Före datahämtning läser jobbet tidpunkten för senaste lyckade publicering och använder `pxweb2_table_needs_update()` mot SCB:s fulla `updated`-timestamp. Därmed upptäcks även en andra SCB-uppdatering samma kalenderdag. Om tabellen inte är nyare hämtas ingen statistikdata och jobbet loggar `no_change` via den nyckelskyddade endpointen `/api/public/jobs/etl-no-change`. RUS-fältet `kalla_uppdaterad_datum` sparas fortsatt som datum.

<!-- Preview rebuild triggered at 2026-09-21T10:55:00Z -->
