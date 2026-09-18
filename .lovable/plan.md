# Iteration: koppla till GitHub och dokumentera för vidareutveckling

Målet är att projektet ska finnas i ett GitHub-repository under angiven organisation, och att kodbasen är tillräckligt dokumenterad för att du och andra ska kunna jobba vidare direkt från GitHub — antingen i Lovable, lokalt eller båda samtidigt.

## Vad du behöver göra innan vi börjar

1. **Ha ett GitHub-konto och tillgång till organisationen.** Du behöver vara medlem i organisationen där repositoryt ska skapas.
2. **Behörighet att installera GitHub App.** Om repositoryt ska ligga i en organisation behöver du antingen vara ägare/admin, eller få en organisationsägare att godkänna installationen av Lovable GitHub App.
3. **Starta GitHub-kopplingen i Lovable.** Det görs via gränssnittet: Plus-menyn (nere till vänster) → GitHub → Connect project → välja organisation/konto → Create Repository. Jag kan inte starta den åt dig eftersom den kräver ditt inloggade GitHub-konto och val av organisation.

## Vad vi bygger i iterationen

### 1. GitHub-koppling (handledning + validering efter att du kopplat)

- Bekräfta att projektet synkas till GitHub (tvåvägs-synk finns redan i Lovable).
- Kontrollera att `.gitignore`, `.prettierignore` och liknande inte blockerar filer som behövs.
- Se till att inga Lovable-specifika hemligheter eller miljövariabler ligger i koden.

### 2. Dokumentationsmapp `docs/`

Tre filer i en ny `docs/`-mapp:

- **`docs/README.md`** — översikt: syfte med projektet, var README:n i rot och andra docs-filer hör hemma, var man hittar designsystem, navigation och data.
- **`docs/komponenter.md`** — komponentkatalog:
  - `components/layout/` (Header, DesktopNav, MobileNav, Footer, Logo, Section, AppLink)
  - `components/ui/` (PageHeader, MetadataList, ExampleBadge m.fl.)
  - `components/charts/` (TimeSeriesChart, IndicatorPanel)
  - För varje: vad den gör, viktigaste props, och var den används.
- **`docs/utveckla.md`** — utvecklarflöde:
  - Kom igång lokalt (`bun install`, `bun run dev`).
  - Filstruktur och viktiga konventioner (inga hex-värden i komponenter, menyn i `config/navigation.ts`, data via `lib/indicators.ts`).
  - GitHub-arbetsflöde: grenar, PR, synk Lovable ↔ GitHub.
  - Vad som inte ska ändras för hand (`routeTree.gen.ts`, auto-genererade filer).

### 3. Rot-README uppdateras

- Länkar till `docs/`-filerna.
- Kortare, tydligare översikt som pekar på detaljerna.
- Sektion om GitHub-utveckling (kort version med länk till `docs/utveckla.md`).

### 4. Konfigurationsgranskning

- Kontrollera `.gitignore` så att byggmappar, Lovable-specifika filer och eventuella `.env`-filer exkluderas.
- Granska att inga onödiga genererade filer checkas in.

## Vad som väntar (inte denna iteration)

- Bidragarguide för flera utvecklare.
- CI/CD och automatiska tester.
- Versionshantering av data eller migreringar.
- Komplett informationsarkitektur, riktig logotyp, figurer och indikatorer.

## Tekniskt

- Ingen ny kod behöver installeras eller byggas; iterationen handlar om dokumentation och GitHub-konfiguration.
- Allt material skrivs på svenska för att matcha projektets övriga dokumentation.

## Nästa steg efter denna iteration

1. Byt ut placeholder-logotyp och meny när informationsarkitekturen är klar.
2. Lägg in riktiga figurer och illustrationer.
3. Definiera de första riktiga indikatorerna.
