# Arkitektur: backend, datalagring och automatiska datauppdateringar (v2)

Arkitekturplan efter teknisk granskning. Inget implementeras förrän du godkänner.

## Förändring mot första förslaget

**Största ändringen:** ETL-flödet rekommenderas nu köras i **GitHub Actions med era befintliga R-skript**, som skriver direkt till Lovable Cloud Postgres. Se jämförelsen nedan — era fungerande R-flöden är den tydliga vinsten. pg_cron-varianten beskrivs som alternativ.

## Rekommenderad arkitektur (efter granskning)

- **Databas:** Lovable Cloud (Postgres). Statistik, metadata, dokumentregister, roller, uppdateringshistorik.
- **Fillagring:** Lovable Cloud Storage för PDF/Excel/bilder/analyser. Profilgrafik och ikoner ligger kvar i `src/assets` i repot.
- **ETL/scheduler:** GitHub Actions (morgonjobb) som kör era R-skript mot SCB/Kolada/Trafikanalys och skriver till Postgres. Jobbnyckel och databasanslutning som GitHub Actions-secrets.
- **Backend i appen:** TanStack server functions för läsning och appintern logik; server routes under `/api/public/*` endast för framtida webhooks/triggers.
- **Autentisering:** Lovable Cloud Auth + separat `user_roles`-tabell (`admin`, `editor`, `registered`) med `has_role()`-funktion; roller aldrig på profilen.
- **AI/RAG:** Lovable AI (chatt + embeddings) med pgvector i samma databas; chattverktyg gör exakta SQL-uppslag mot statistiktabellerna.
- **GitHub:** all kod, R-skript, migrationsfiler, GitHub Actions-workflows, dokumentation. Inga hemligheter eller data.

## Svar på granskningsfrågorna

### Portabilitet

Ja. Databasen kan exporteras (schema + data) från Cloud → Advanced settings och är kompatibel med vanlig Postgres — den kan flyttas till en annan Supabase/Postgres-miljö utan applikationsombyggnad. Eftersom appen är vanlig React/Vite och databaskoden går via standardklienten är det i praktiken en ny anslutningssträng som skiljer. Undantag: filer i Storage, eventuella hemligheter och körda migrationers historik hanteras separat. Exportgräns: upp till 15 GB data.

### Backup

Automatiska dagliga backuper, cirka 14 dagars retention, återställning via Cloud-inställningarna. **Ingen point-in-time recovery** — återställning sker till senaste dagliga ögonblicksbild och skriver över allt efter det. Konsekvens för oss: statistik kan alltid återskapas via ETL-omkörning (källan är SCB m.fl.), men uppladdade dokument och redaktionellt innehåll är det enda som inte kan återskapas — därför bör kritiska originalfiler även speglas utanför (t.ex. GitHub eller organisationens egen lagring) om de är svårersättliga.

### Datalokalisering

Region väljs när Cloud aktiveras (Americas / Europe / Asia Pacific) och kan **inte ändras i efterhand**. Vi väljer Europa vid aktivering. Regionvalet gäller databas, Auth och Storage. På Business/Enterprise kan organisationen tvinga EU som standard. Detta bör dokumenteras mot Region Norrbottens informationssäkerhetskrav innan inloggning/personuppgifter slås på.

### Miljöer

Lovable har **en** Cloud-miljö per projekt — ingen automatisk separation dev/staging/prod med egna databaser. Utveckling sker mot samma databas som sedan publiceras. Vill vi ha isolerad testmiljö blir det ett separat Lovable-projekt (egen databas, egen storage). Pragmatisk modell för oss: testmarkör på data (`isExample`/körningslogg) och försiktighet med migrationsordning, hellre än dubbla projekt i detta skede. GitHub Actions-jobben kan riktas mot samma databas oavsett.

### Migrationer

Schemaändringar görs som SQL-migrationer som ligger i repot och versionshanteras via tvåvägssynken med GitHub — samma katalogstruktur, reproducerbara från tomt schema. Det uppfyller kravet att allt strukturellt ska kunna återskapas från GitHub.

### Schemaläggning — två alternativ jämförda

**Alternativ A (rekommenderas): GitHub Actions + era R-skript**

```text
GitHub Actions (cron 05:00)
  -> R-skript: hämta metadata från SCB
  -> jämför mot senast publicerat i tabellen indicator_metadata
  -> vid ändring: full hämtning -> validering -> transformation (befintlig R-kod)
  -> skriv till Lovable Cloud Postgres (direkt DB-anslutning)
  -> logga körning i data_source_runs
Webbplatsen läser alltid från Postgres vid sidladdning — aldrig externa API:er.
```

- Återanvänder era fungerande transformationer; ingen omskrivning till TypeScript.
- Ingen tidsgräns att oroa sig för: Actions-jobb kan köra länge, R har mogna SCB-/pxweb-bibliotek.
- Nycklar (databas-URL, ev. API-nycklar) ligger som GitHub Actions-secrets — aldrig i repot.
- Kräver att repot är kopplat (vilket ni redan gjort/påbörjat).

**Alternativ B: pg_cron -> server route i appen**

pg_cron i databasen anropar varje morgon en nyckelskyddad endpoint (`/api/public/jobs/scb-refresh`). Nyckeln lagras som hemlighet i Lovable (inte i repot), endpointen verifierar den innan något körs, och obehöriga anrop avvisas med 401. Nackdelar som väger tungt här: all transformationslogik måste skrivas om i TypeScript, serverkoden körs i en edge-miljö med begränsad körtid (se nedan), och stora SCB-hämtningar måste styckevis delas upp.

**Rekommendation:** Alternativ A, särskilt med många indikatorer och flera källor. Alternativ B blir aktuellt först om ni vill konsolidera allt i Lovable och är beredda att skriva om R-flödena — det finns ingen teknisk vinst som motiverar det nu.

### Retries, samtidighet, idempotens

Gäller oavsett alternativ:

- **Körningslogg:** varje körning skapar en rad i `data_source_runs` (status: started/succeeded/failed/no_change, antal rader, felmeddelande).
- **Låsning:** körningen markerar indikatorn som "pågår" och avböjer om en körning redan pågår (databasvillkor/advisory lock) — förhindrar dubbla samtidiga körningar.
- **Idempotens:** skrivning per indikator+period ersätter/upsert:ar, aldrig blidirar — en omkörning ger samma sluttillstånd.
- **Retry:** misslyckad körning lämnar befintlig publicerad data orörd; nästa morgonjobb försöker igen automatiskt. Vid fel i valideringen sparas inget. Manuell omkörning möjlig (workflow_dispatch i GitHub Actions).
- **Timeout:** Actions-jobb får generös tidsgräns; i alternativ B hade stora hämtningar behövt delas per indikator/år.

### Serverbegränsningar i Lovable (relevant för webbplatsen)

Serverfunktioner/server routes körs i en serverless edge-miljö:

- Ingen långvarig process; buffrade anrop som inte skickar data på ~2 minuter bryts — därför streamas AI-anrop.
- Inga tunga Node-specifika bibliotek (ingen child_process, inga nativa binärer) — Excel/PDF-tolkning i appen måste använda webbanpassade bibliotek eller göras i ETL-steget.
- Tillstånd sparas i databasen, inte i minnet.

Konsekvens: appen läser färdiglagd data snabbt (kort levetid per anrop är inget problem); allt tungt arbete ligger i GitHub Actions/Postgres.

### AI: vad "Lovable AI" faktiskt innebär

- Server-side AI-gateway: nyckeln ligger bara på servern, aldrig i webbläsaren.
- Chatt: standard är en modern resonerande modell; svaren streamas och kan visa tankeprocess. Modellen kan bytas per funktion.
- Embeddings: standardmodell ger 3072-dimensionella vektorer som lagras i pgvector i samma Postgres; dokumentstyckas (500–1500 tecken) och indexeras för semantisk sökning.
- Kostnad: förbrukas som credits per anrop (tokens); övervakas i projektets AI-panel. Innan AI-chatten byggs gör vi en konkret kostnadsuppskattning.
- Källhänvisningar säkerställs genom design: chatten får verktyg som gör exakta SQL-uppslag (siffror gissas aldrig) och RAG-svar citerar dokument/indikator med källa och datum från metadatafälten.

### GitHub Actions som ETL — slutbedömning

Med era omfattande R-flöden är hybriden överlägsen: omräkningen av transformationer till TypeScript är en ren kostnad utan funktionell vinst, och Actions ger längre körtider, mognare statistikbibliotek och enkel manuell omkörning. Lovable-delen begränsas till det den är bäst på: lagring, webbplats, auth, AI.

## Uppdaterat dataflöde

```text
  SCB / Kolada / Trafikanalys
            |
            v
  GitHub Actions 05:00 (R-skript, i repot)
   - metadatakontroll mot indicator_metadata
   - ingen ändring -> logga no_change, klart
            | ändring
            v
  full hämtning -> validering -> transformation (R)
            |
            v
  Lovable Cloud Postgres (indikatorer, observationer, metadata, körningslogg)
            |
            v
  TanStack-webbplats: route loaders läser Postgres
            |
            +--> diagram, tabeller, kartor
            +--> AI-chatt (SQL + pgvector mot samma databas)
```

## Slutlig rekommendation

| Område | Rekommendation |
| --- | --- |
| Databas | Lovable Cloud Postgres (region: Europa vid aktivering) |
| Fillagring | Lovable Cloud Storage (publik + skyddad bucket) |
| Scheduler/ETL | GitHub Actions + befintliga R-skript, skriver till Postgres |
| Autentisering | Lovable Cloud Auth + separat `user_roles`-tabell |
| Backendfunktioner | TanStack server functions / server routes i appen |
| AI/RAG | Lovable AI + pgvector i samma databas; källhänvisning via metadata |
| GitHub | Kod, R-skript, migrationer, workflows, dokumentation |

## Byggordning

1. Aktivera Lovable Cloud (region Europa), skapa datamodellen, flytta exempelindikatorn dit.
2. GitHub Actions-workflow: metadatakontroll + full hämtning för en SCB-indikator, körningslogg.
3. Statussida i webbplatsen som visar senaste körningar per indikator.
4. Inloggning/roller, sedan dokumentuppladdning (Storage).
5. AI-chatt med RAG — efter separat genomgång av kostnad, GDPR och förvaltning.
