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

> Just nu används inga externa API:er, databaser eller inloggning. Inga miljövariabler behövs för att köra projektet lokalt.

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
4. **Logotyp som asset.** Logotypen importeras som SVG från `src/assets/logo/`. Byt filen, inte komponenten.
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

1. Fastställ informationsarkitektur och byt ut placeholder-menyn i `src/config/navigation.ts`.
2. Byt ut `src/assets/logo/kompetensarena-placeholder.svg` mot riktig logotyp.
3. Lägg in valda figurer och illustrationer från presentationsmaterialet i `src/assets/`.
4. Definiera de första riktiga indikatorerna (ersätt exempelindikatorn i databasen) och koppla på ETL-flödet (GitHub Actions + R-skript) mot SCB.
5. Bygg inloggning och roller, därefter dokumentuppladdning.
6. AI-chatt med källhänvisning — efter separat genomgång av kostnad, GDPR och förvaltning.
