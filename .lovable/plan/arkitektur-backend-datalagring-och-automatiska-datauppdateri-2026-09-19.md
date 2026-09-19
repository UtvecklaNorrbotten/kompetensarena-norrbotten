# Arkitektur: backend, datalagring och automatiska datauppdateringar (v3 — godkänd i huvudsak)

Arkitekturplan. Inget implementeras förrän ni startar första byggsteget.

## Grundprinciper (fastställda)

- **Databas:** Lovable Cloud Postgres, region **Europa** (väljs vid aktivering, kan inte ändras efteråt).
- **Fillagring:** Lovable Cloud Storage (publik + skyddad bucket). Profilgrafik/ikoner ligger kvar i `src/assets`.
- **ETL/scheduler:** GitHub Actions som kör era befintliga R-skript mot SCB/Kolada/Trafikanalys och skriver till Postgres.
- **Frontend/backend i appen:** TanStack Start i befintligt repo; server functions för läsning/appintern logik, server routes endast för framtida webhooks/triggers.
- **Autentisering:** Lovable Cloud Auth + separat `user_roles`-tabell med `has_role()`; roller aldrig på profilen.
- **AI:** eget serverlager (`AIService`) mellan chatt och provider — providern är utbytbar.
- **GitHub:** kod, R-skript, migrationer, workflows, dokumentation. Ingen driftdata, inga hemligheter.

## Förtydliganden som styr designen

### 1. Dedikerad ETL-databasroll med minsta möjliga behörighet

GitHub Actions ansluter **inte** med en fullprivilegierad nyckel. Vi skapar i Postgres:

- En dedikerad databasroll, t.ex. `etl_writer`, med eget lösenord (lagras som GitHub Actions-secret).
- Behörigheter begränsade till exakt det som behövs:
  - `SELECT` på `indicators`, `geographies` (läs av nycklar/definitioner).
  - `INSERT, UPDATE` på `indicator_metadata`, `data_source_runs` (körningslogg och hämtstatus).
  - **Ingen direkt behörighet alls** på `observations` — varken INSERT, UPDATE eller DELETE.
  - **Inga** rättigheter till `user_roles`, auth-tabeller, dokumentregister eller adminfunktioner.
  - Ingen rätt att skapa/ändra tabeller (DDL görs bara via migrationer).
- **Atomisk publicering via låst databasfunktion.** Eftersom källors tabeller förändras (perioder/rader kan försvinna) räcker inte ren upsert — men ETL-rollen ska heller inte kunna utföra godtyckliga DELETE. Lösningen är en RPC i Postgres, t.ex. `publish_indicator(indikator_id, observationer jsonb, metadata jsonb)`, som:
  - är `SECURITY DEFINER` (ägs av migrationsrollen) och därmed får ersätta data — men **endast** inom funktionens fasta logik,
  - i en enda transaktion: tar advisory lock per indikator, raderar befintliga observationer **för just den indikatorn**, sätter in det nya, validerade datasetet, uppdaterar `indicator_metadata` (`hamtad_datum`, `kalla_uppdaterad_datum`) och skriver körningsloggrad — allt eller inget,
  - avvisar anrop för indikator som inte finns eller där anropet saknar obligatoriska fält,
  - aldrig kan röra andra indikatorer, andra tabeller eller utföra fria DELETE-operationer.
- `etl_writer` får exakt en rättighet mot observationsdata: `EXECUTE` på `publish_indicator`. Revokera `EXECUTE` från `PUBLIC` och ge den bara till `etl_writer`.
- Rot-/service-nycklar används aldrig av ETL och finns aldrig i GitHub.

### 2. Metadatamodell enligt era RUS-konventioner

Ingen parallell begreppsmodell. Tabellen för indikatormetadata använder era fält:

- `kalla_uppdaterad_datum` — när källan publicerade nytt data.
- `hamtad_datum` — när vi hämtade datat.
- `tillganglighetsdatum` — beräknat fält: `coalesce(kalla_uppdaterad_datum, hamtad_datum)`.
- `styrande_kalla` — den källa som styr indikatorn.

Övriga metadatafält (källans namn, tabell-id, frekvens, anmärkning) kompletterar, inte ersätter, dessa. Samma fält används i UI-metadata (källa, senast uppdaterad) så att begreppen är identiska genom hela kedjan.

### 3. Automatisk publicering från säkra källor — atomiskt

För betrodda källor (SCB m.fl.) finns **ingen manuell godkännandefas**:

```text
metadatakontroll -> ny data? -> hämta -> teknisk validering -> publicera automatiskt
```

Krav på flödet:

- Hämtning + validering sker på rådata i minnet/staging — inget skrivs till publicerade tabeller förrän valideringen godkänts.
- Publicering sker **atomiskt i en transaktion** via den låsta RPC-funktionen `publish_indicator` (se avsnittet om ETL-rollen): gamla observationer för indikatorn ersätts av det nya datasetet — allt eller inget. ETL-rollen kan aldrig utföra fria DELETE eller påverka andra indikatorer.
- Vid fel i hämtning eller validering: transaktionen rullas tillbaka, befintlig publicerad data ligger kvar orörd, felet loggas i `data_source_runs` med status `failed` och felmeddelande. Inget halvfärdigt dataset kan bli synligt.
- Statusvärden i körningsloggen: `started`, `no_change`, `succeeded`, `failed`.

### 4. Tre behörighetsnivåer för data — skyddade i databasen

Varje indikator (och senare varje dokument) får en synlighetsnivå: `publik`, `inloggad`, `admin`.

- Skyddet ligger i **RLS-policies i databasen + server-side filtrering**, inte i frontend. Frontend visar bara det servern levererar.
- `publik`: läsbar av alla (policy `TO anon`).
- `inloggad`: kräver autentiserad session.
- `admin`: kräver rollen `admin` via `has_role()` — kontrolleras server-side, aldrig via klientlagring.
- Diagram-/tabellkomponenterna behöver ingen behörighetslogik — de får bara den data anroparen får se.

### 5. Utbytbart AI-lager

Arkitekturen isolerar providern:

```text
Chat UI (AI Elements) -> vår server route/server function -> AIService (eget gränssnitt) -> provider
```

- `AIService` är en intern modul med ett litet gränssnitt: `chat(messages, tools)`, `embed(text)`. Lovable AI är första implementationen.
- Chattens verktyg (SQL-uppslag mot statistik, vektorsök i dokument) är providerneutrala — de returnerar data, providern formulerar svaret.
- Byte till t.ex. OpenAI direkt-API innebär en ny implementation av `AIService` — chatten, verktygen, lagringen och UI:t är oförändrade.
- Embeddings lagras med modellbeteckning i databasen så att en framtida ominbäddning är möjlig vid providerbyte.
- Källhänvisningar: verktygen returnerar källa + `tillganglighetsdatum` per siffra/dokument; systeminstruktionen kräver att svaren citerar dessa.

## Datamodell (uppdaterad)

- `indicators` — id, namn, beskrivning, enhet, `styrande_kalla`, källtabell-id, frekvens, **synlighetsnivå**.
- `geographies` — kod, namn, nivå (riket/län/kommun), överordnad kod.
- `observations` — indikator, geografi, period, värde, dimensioner (kön/ålder/bransch) som nyckelvärden.
- `indicator_metadata` — `kalla_uppdaterad_datum`, `hamtad_datum`, `tillganglighetsdatum` (genererad kolumn), `styrande_kalla`, källa, anmärkning.
- `data_source_runs` — källa, indikator, starttid, sluttid, status (`started`/`no_change`/`succeeded`/`failed`), antal rader, felmeddelande.
- `documents` — titel, typ, filreferens (Storage), kopplad indikator, uppladdare, **synlighetsnivå**.
- `user_roles` — `admin`, `editor`, `registered` (separat tabell enligt säkerhetsmönstret).
- Senare: `document_chunks` med pgvector-embeddings + modellbeteckning.

Databasroller: `etl_writer` (ovan), appens vanliga användarroller via RLS, service-roll endast för migrations- och adminjobb.

## Dataflöde (fastställt)

```text
  SCB / Kolada / Trafikanalys
            |
            v
  GitHub Actions 05:00 (R-skript, ansluter som etl_writer)
   - metadatakontroll mot indicator_metadata
   - ingen ändring -> logga no_change, klart
            | ändring
            v
  hämta -> teknisk validering (R)     [fel -> rulla tillbaka, logga, gamla data kvar]
            |
            v
  atomisk publicering (transaktion/upsert) + uppdatera hamtad_datum
            |
            v
  Lovable Cloud Postgres (RLS styr publik/inloggad/admin)
            |
            v
  TanStack-webbplats: server functions läser Postgres
            |
            +--> diagram, tabeller, kartor (efter behörighet)
            +--> Chat UI -> serverfunktion -> AIService -> Lovable AI
                       (verktyg: SQL-uppslag + pgvector-sök, med källhänvisning)
```

## Robusthet och drift (sammanfattning)

- Dagliga databasbackuper ~14 dagar (ingen point-in-time recovery). Statistik kan alltid återskapas via ETL-omkörning; svårersättliga uppladdade original speglas vid behov utanför.
- Låsning mot samtidiga körningar: advisory lock per indikator; körning som redan pågår avböjer ny start.
- Retry: misslyckad körning provas igen av nästa schemalagda jobb; manuell omkörning via `workflow_dispatch`.
- En Cloud-miljö per projekt — exempel/testdata markeras (`isExample`), inga separata staging-databaser i detta skede.
- Migrationer i repot, reproducerbara från tomt schema.

## Byggordning

1. Aktivera Lovable Cloud (region Europa). Migration: datamodell + `etl_writer`-roll + RLS-policies + flytta exempelindikatorn.
2. GitHub Actions-workflow + R-skript: metadatakontroll, validering, atomisk publicering, körningslogg — för en första SCB-indikator.
3. Statussida i webbplatsen: senaste körningar, tillgänglighetsdatum och källa per indikator.
4. Inloggning + roller (`user_roles`), synlighetsnivåer i UI, därefter dokumentuppladdning (Storage).
5. AI-chatt: `AIService`-gränssnitt + Lovable AI som första provider, RAG med källhänvisning — efter separat genomgång av kostnad, GDPR och förvaltning.
