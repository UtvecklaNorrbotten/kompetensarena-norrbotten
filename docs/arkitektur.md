# Teknisk arkitektur

## Målbild

Kompetensarena Norrbotten ska separera datainsamling, lagring, webbapplikation och AI så att varje del kan utvecklas och bytas oberoende.

```text
SCB / Kolada / Trafikanalys
        |
        v
GitHub Actions + R
        |
        v
nyckelskyddad ETL-endpoint
        |
        v
publish_indicator(...)
        |
        v
Lovable Cloud Postgres
        |
        +--> TanStack Start --> diagram / tabeller / kartor
        |
        +--> AIService --> vald AI-provider
```

Webbplatsen ska aldrig vara beroende av externa statistik-API:er vid sidladdning.

## Ansvar per lager

### GitHub

Versionshanterar:

- TanStack/React-kod
- R-skript
- GitHub Actions-workflows
- databasmigrationer
- konfiguration
- dokumentation
- profilgrafik och små statiska referensfiler

GitHub ska inte innehålla driftdata, uppladdade känsliga filer eller hemligheter.

### Lovable Cloud Postgres

Lagrar:

- indikatorer
- observationer
- geografier
- metadata
- körningslogg
- dokumentregister
- användarroller

Metadata följer RUS-konventionerna:

- `kalla_uppdaterad_datum`
- `hamtad_datum`
- `tillganglighetsdatum`
- `styrande_kalla`

`tillganglighetsdatum` motsvarar `coalesce(kalla_uppdaterad_datum, hamtad_datum)`.

### Lovable Cloud Storage

Används för större filer, till exempel PDF, Excel, bilder och analyser.

Skyddade filer ska aldrig exponeras med permanenta publika länkar. Åtkomst ska styras server-side och med signerade länkar där det behövs.

## Behörighetsnivåer

Tre nivåer används genomgående:

1. `publik`
2. `inloggad`
3. `admin`

Skyddet ska ligga i databas/RLS och serverlogik, inte endast i gränssnittet.

Den mest känsliga informationen ska endast vara åtkomlig för administratörer.

## ETL-princip

Varje morgon kontrollerar ETL-flödet metadata för relevanta källor.

```text
metadatakontroll
  |
  +-- ingen ändring --> logga no_change
  |
  +-- ändring --> hämta --> transformera --> teknisk validering
                                      |
                                      +-- fel --> behåll tidigare data
                                      |
                                      +-- OK --> publicera atomiskt
```

Betrodda källor som SCB kräver ingen manuell godkännandefas. Om hämtning och teknisk validering lyckas publiceras data automatiskt.

## Publicering

GitHub Actions ska inte ha generell databasåtkomst.

Validerad data skickas till en särskild nyckelskyddad endpoint. Endpointen får endast publicera via den begränsade databasfunktionen `publish_indicator`.

Publiceringen ska vara atomisk: antingen ersätts hela indikatorns aktuella dataset korrekt, eller så ändras ingenting.

## AI

AI-funktioner ska ligga bakom ett eget serverlager.

```text
Chat UI
  |
  v
serverfunktion / API
  |
  v
AIService
  |
  v
provider
```

Första provider kan vara Lovable AI, men webbplatsen ska inte vara beroende av en specifik AI-leverantör.

Strukturerade siffror ska hämtas med exakta databasuppslag. Dokumentbaserade svar kan senare använda RAG/pgvector. Behörighetsnivåerna måste respekteras även i AI-verktygen; AI får aldrig kringgå RLS eller ge en användare data som denne inte annars får läsa.

## Driftprinciper

- Misslyckad ETL får aldrig förstöra tidigare publicerad data.
- Varje körning loggas.
- Om en indikator redan uppdateras ska parallell körning för samma indikator avvisas/låsas.
- Hemligheter lagras i GitHub Actions Secrets eller Lovable secrets, aldrig i repot.
- Databasmigrationer ska vara reproducerbara från GitHub.
