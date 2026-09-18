# Komponentkatalog

Komponenterna ligger i `src/components/` och är uppdelade i tre grupper:

- `layout/` — sidans ram: header, navigation, footer, sektioner, logotyp, länkhjälpare.
- `ui/` — små återanvändbara byggstenar.
- `charts/` — diagram och presentation av indikatorer.

Konventionen är att komponenterna är små, namngivna efter vad de gör, och att konfiguration (menytext, sidtitel, indikatordata) skickas in som props eller läses från `src/config/` och `src/lib/`, aldrig hårdkodas i UI-komponenten.

---

## `src/components/layout/`

### `AppLink`

Wrapper runt TanStacks `Link` som accepterar en vanlig sträng som `href`.

**Används för:** länkar där målet kommer från konfigurationsfiler (t.ex. navigationen) och därför inte kan vara en typad route-literal.

**Props:**

- `href: string` — sökväg, t.ex. `"/statistik"` eller `"/kommer-senare"`.
- Övriga props skickas vidare till `Link`.

### `DesktopNav`

Desktopnavigation med undermenyer.

**Beteende:**

- Undermeny öppnas vid hover och vid klick på pilen.
- Fördröjd stängning vid hover så att musen hinner in i panelen.
- Tangentbordsstöd: Tab fokuserar huvudposten, Enter/Space öppnar/stänger, nedåtpil öppnar, Escape stänger och återför fokus.
- Fokuslämnande stänger undermenyn.

**Data:** Läser `mainNavigation` från `src/config/navigation.ts`.

### `MobileNav`

Hamburgermeny för mobil och små skärmar.

**Beteende:**

- Öppnar en helskärmspanel.
- Undermenyer fälls ut med knapp bredvid varje huvudpost.
- Escape stänger panelen.
- Kroppens scroll låses när panelen är öppen.

**Data:** Läser `mainNavigation` från `src/config/navigation.ts`.

### `Header`

Sidhuvudet. Sticky header med logotyp, desktopnavigation och mobilnavigation.

**Notering:** Ingen `backdrop-blur` används eftersom det skapar en containing block och bryter mobilmenyns fixed-positionering.

### `Footer`

Sidfot med mörkgrön bakgrund. Visar plattformens namn, tagline, ägare och kontaktmail.

**Data:** Läser `site` från `src/config/site.ts`.

### `Logo`

Logotypen behandlas som grafisk asset (SVG), inte som text.

**Notering:** Filen `src/assets/logo/kompetensarena-placeholder.svg` är en platshållare och ska bytas mot riktig logotyp från Utveckla Norrbotten.

### `Section`

Gemensam sektionsram som håller luft, bakgrundsytor och innehållsbredd konsekventa.

**Props:**

- `children: ReactNode`
- `tone?: "default" | "light" | "neutral" | "dark" | "surface"` — bakgrundsfärg enligt designsystemet.
- `width?: "content" | "prose"` — maxbredd (`content` = 76 rem, `prose` = 44 rem).
- `className?: string`
- `id?: string`

---

## `src/components/ui/`

### `PageHeader`

Sidhuvud med valfri överrubrik (eyebrow), huvudrubrik och introduktionstext.

**Props:**

- `eyebrow?: string`
- `title: string`
- `intro?: string`

### `MetadataList`

Visar metadata för en indikator: källa, senast uppdaterad, geografisk nivå och period.

**Props:**

- `metadata: IndicatorMetadata`

**Data:** Översätter `geoLevel` till svenska etiketter (Riket / Län / Kommun).

### `ExampleBadge`

Etikett som tydligt märker innehåll som exempeldata.

**Props:**

- `children?: string` — standardtext är `"Exempeldata"`.

---

## `src/components/charts/`

### `TimeSeriesChart`

Återanvändbart tidsseriediagram. Komponenten känner inte till någon specifik indikator — den tar emot datapunkter och enhet som props.

**Props:**

- `data: TimeSeriesPoint[]`
- `unit: string` — visas i tooltip och figurtext.
- `ariaLabel: string` — beskrivning för skärmläsare.

**Implementation:** Använder Recharts (`LineChart`). Recharts är inkapslat i denna fil, så biblioteket kan bytas utan att sidor eller andra komponenter behöver ändras.

### `IndicatorPanel`

Standardmönstret för hur en indikator presenteras: rubrik, beskrivning, "Exempeldata"-märkning, diagram och metadata.

**Props:**

- `indicator: Indicator`

**Används på:** `/statistik`.
