# Kompetensarena Norrbotten

Kunskaps- och analysportal för statistik, analyser och kunskap om kompetensförsörjning
i Norrbotten. En del av Utveckla Norrbotten.

Projektet utvecklas stegvis. Den här versionen (iteration 1) innehåller den visuella
och tekniska grunden: grafisk profil, navigation, responsiv layout, ett fåtal sidor och
ett enda statistikexempel.

## Teknisk stack

| Del | Val | Kommentar |
| --- | --- | --- |
| Ramverk | TanStack Start (React 19 + Vite) | Filbaserad routing i `src/routes` |
| Styling | Tailwind CSS v4 | Designtokens i `src/styles.css` (ingen `tailwind.config.js`) |
| Diagram | Recharts | Inkapslat i `src/components/charts` och därmed utbytbart |
| Ikoner | lucide-react | Endast gränssnittsikoner |

Inga externa tjänster används: ingen databas, ingen inloggning, ingen analystjänst,
inga AI-anrop. Koden är vanlig React/Vite och kan klonas, byggas och vidareutvecklas
via GitHub utan Lovable.

## Kom igång

```bash
bun install   # eller npm install
bun run dev   # startar utvecklingsserver
```

## Katalogstruktur

```
src/
  routes/          sidor: / (start), /om, /statistik, /kommer-senare
  components/
    layout/        Header, DesktopNav, MobileNav, Footer, Logo, Section
    ui/            små återanvändbara byggstenar (PageHeader, MetadataList m.m.)
    charts/        visualiseringar (TimeSeriesChart, IndicatorPanel)
  config/          navigation.ts (menyn), site.ts (namn, kontakt, texter)
  data/            typer och exempeldata
  lib/             datalager (indicators.ts) och hjälpfunktioner
  assets/          grafiska resurser, se src/assets/README.md
  styles.css       designsystem: färger, typografi, spacing, radier, states
```

## Designsystem

Alla designvärden definieras på ett ställe i `src/styles.css`:

- Profilfärger som CSS-variabler och semantiska roller
  (`--background`, `--primary`, `--surface`, `--border` …).
- Typografi: Titillium Web (rubriker) och Roboto/Roboto Light (brödtext).
- Radier, innehållsbredd (`--container-content`, `--container-prose`) och
  fokusmarkering.

Hårdkoda aldrig hex-värden i komponenter – använd klasser som `bg-brand-light`,
`text-brand-dark`, `text-ink-muted`.

**Tillgänglighet:** orange, ljusorange och ljusgrön används som ytor, aldrig som
textfärg mot ljus bakgrund. Fokusmarkering är synlig globalt, navigationen fungerar
med enbart tangentbord och sidan har en "hoppa till innehåll"-länk.

## Navigation

Menyns innehåll ligger i `src/config/navigation.ts` och är **placeholder**.
Byt rubriker och poster där – komponenterna behöver inte ändras.

- Desktop (`DesktopNav`): undermeny öppnas vid hover och vid klick, stängs med Escape
  eller när fokus lämnar gruppen.
- Mobil (`MobileNav`): helskärmspanel med utfällbara undermenyer.
- Länkar som saknar sida pekar på `/kommer-senare`.

## Data

`src/lib/indicators.ts` är ett tunt datalager. Idag returnerar det exempeldata från
`src/data/example-indicators.ts`. När riktiga källor tillkommer (filimport, API,
databas) byts implementationen där – sidor och komponenter är oförändrade eftersom de
bara anropar `listIndicators()` / `getIndicator()`.

Alla indikatorer beskrivs med samma typer (`src/data/types.ts`): metadata om källa,
uppdateringsdatum, geografisk nivå och period plus datapunkter.

## Vad som är tillfälligt i denna version

- Logotypen i `src/assets/logo/` är en platshållare.
- Menystrukturen är exempel.
- All statistik är påhittad exempeldata och märkt "Exempeldata".
- Sidan `/kommer-senare` fångar upp ännu obyggda menyposter.

## Nästa steg

1. Fastställ informationsarkitektur och byt ut menyn.
2. Lägg in riktig logotyp samt valda figurer och illustrationer.
3. Definiera de första riktiga indikatorerna och deras datamodell.
4. Diskutera behov av databas, inloggning, AI och webbstatistik – med alternativ,
   kostnad, GDPR och förvaltning – innan något implementeras.
