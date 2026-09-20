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

1. Koppla den första riktiga indikatorn, E3 från SCB TAB6929, till ETL-flödet.
2. Generalisera GitHub Actions + R-flödet för fler indikatorer och datakällor.
3. Bygg statussida för datauppdateringar och metadata.
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
