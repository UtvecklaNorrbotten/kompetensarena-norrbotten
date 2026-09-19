# Arkitektur: backend, datalagring och automatiska datauppdateringar

Detta är en arkitekturplan, inte en byggplan. Inget implementeras förrän du godkänner.

## Rekommenderad huvudarkitektur (kort)

- **Databas:** Lovable Cloud (Postgres). Strukturerad statistik, metadata och uppdateringshistorik.
- **Fillagring:** Lovable Cloud Storage (objektlagring) för PDF, Excel, bilder. Endast profilgrafik/ikoner ligger kvar i `src/assets` i repot.
- **Scheduler:** `pg_cron` i databasen som varje morgon anropar en publik, nyckelskyddad endpoint i appen (`/api/public/jobs/scb-refresh`).
- **Backendfunktioner:** TanStack server functions (`createServerFn`) för appintern logik, server routes under `src/routes/api/public/*` för jobb och webhooks. Ingen separat backend-tjänst.
- **Autentisering:** Lovable Cloud Auth (e-post/lösenord, ev. Google) med separat `user_roles`-tabell och rollkontroll i databasen.
- **AI/RAG:** Lovable AI för både chatt och embeddings; `pgvector` i samma databas för dokument- och textsök, plus direkta SQL-uppslag mot indikatortabellerna.
- **GitHub:** all kod, migrationer, transformationslogik och dokumentation. Inga hemligheter, ingen rådata, inga uppladdade filer.

Detta är ett sammanhållet alternativ: en databas, en lagring, en kodbas, en driftmiljö.

## Enklare alternativ

Om ni vill vänta med databas: hämta SCB-data i ett schemalagt GitHub Actions-jobb, spara resultatet som JSON-filer i repot och låt webbplatsen läsa dessa filer. Fungerar för ett fåtal indikatorer och kostar inget extra, men klarar inte uppladdade dokument, inloggning, AI-chatt eller stora datamängder — och versionshistoriken sväller. Rekommenderas bara som mellansteg.

## Dataflöde

```text
  SCB / Kolada / Trafikanalys (externa API:er)
            |
            v
  [1] Schemalagt jobb, varje morgon 05:00
      pg_cron i databasen anropar endpoint i appen
            |
            v
  [2] Metadatakontroll (server, i appen)
      hämtar tabellens senaste publiceringsdatum
      jämför med senast sparat värde per indikator
            |
       nytt data?  -- nej --> logga "ingen ändring" -> klart
            | ja
            v
  [3] Full datahämtning (server, i appen)
      med timeout, retry och backoff
            |
            v
  [4] Validering + transformering (server, delad kod)
      kontroll av format, perioder, geokoder, rimlighet
      översätt till plattformens gemensamma format
            |
            v
  [5] Lagring (databas)
      indikatorer, observationer, metadata, körningslogg
            |
            v
  [6] Webbplats (server + frontend)
      route loaders läser från databasen, aldrig från SCB
            |
            +--> visualiseringar (diagram, tabeller, kartor)
            +--> AI-chatt (SQL mot statistik + vektorsök i dokument)
```

Var saker körs:

| Steg | Körs var |
| --- | --- |
| 1 Schemaläggning | Databasen (pg_cron) |
| 2–5 Hämtning, validering, lagring | Serverkod i appen |
| 6 Sidladdning | Serverkod läser databas, frontend renderar |
| Uppladdning av filer | Adminvy i appen -> objektlagring |
| AI-chatt | Serverkod -> Lovable AI + databas |

Externa API:er anropas **aldrig** från webbläsaren och aldrig vid sidladdning.

## Svar på dina frågor

**Databas.** Postgres via Lovable Cloud. Tidsserier är relationsdata med metadata — Postgres passar, och samma databas kan senare bära roller, dokumentindex och vektorsök. Ingen separat tjänst behövs.

**Supabase eller Lovables backendfunktioner?** Båda, men de löser olika saker: Lovable Cloud (som är Postgres + auth + storage) är lagringen; TanStack server functions i detta projekt är applikationslogiken. Vi behöver inte Edge Functions — appens egna serverfunktioner räcker och håller all kod i samma repo med samma typer.

**Större filer.** Objektlagring i Lovable Cloud Storage, inte i repot och inte i databasen. Filer får en rad i en `documents`-tabell med titel, typ, koppling till indikator, uppladdare och synlighet. Publika filer i en öppen bucket, interna i en skyddad med signerade länkar.

**Schemaläggning.** `pg_cron` i databasen som varje morgon anropar appens jobb-endpoint. Fördelen mot GitHub Actions: jobbet kör mot samma miljö och samma kod som webbplatsen, och slutar inte fungera om repot flyttas. GitHub Actions är rimligt reservalternativ men kräver egna hemligheter och en separat kopia av logiken.

**Separation.**

```text
src/
  integrations/scb/      API-klient: bara HTTP mot SCB, inget om vår modell
  integrations/kolada/   samma mönster för nästa källa
  lib/etl/               validering + transformering till vårt format
  lib/repositories/      läs/skriv mot databasen
  routes/api/public/     jobb-endpoints (nyckelskyddade)
  lib/*.functions.ts     appintern serverlogik
  components/, routes/   frontend
```

Varje ny datakälla är en ny mapp under `integrations/` som levererar samma normaliserade form. Inget annat behöver ändras.

**Datamodell (utkast).**

- `indicators` — id, namn, beskrivning, enhet, styrande källa, källtabell-id, uppdateringsfrekvens.
- `geographies` — kod, namn, nivå (riket/län/kommun), överordnad kod.
- `observations` — indikator, geografi, period, värde, ev. dimensioner (kön, ålder, bransch) som nyckelvärden.
- `indicator_metadata` — källa, senast publicerat hos källan, hämtat datum, tillgänglighetsdatum, nästa förväntade publicering, anmärkning.
- `data_source_runs` — uppdateringshistorik: källa, starttid, resultat (ingen ändring / uppdaterad / fel), antal rader, felmeddelande.
- `documents` — uppladdade filer med metadata och synlighet.

Historik bevaras genom att observationer versioneras per hämtningstillfälle vid behov, annars ersätts per period.

**Autentisering och roller.** Lovable Cloud Auth. Roller **aldrig** på användarprofilen utan i en separat `user_roles`-tabell (`admin`, `editor`, `registered`) med en säkerhetsfunktion `has_role()` som styr behörighetsreglerna i databasen. Publikt innehåll är läsbart utan inloggning; redigering och interna dokument kräver roll. Detta går att lägga till senare utan att bygga om något — men tabellerna bör skapas med den modellen i åtanke från början.

**AI-chatt / RAG.** Samma databas: `pgvector` för embeddings av dokumenttext och indikatorbeskrivningar, plus verktyg som gör riktiga uppslag mot statistiktabellerna så att siffror hämtas exakt och inte gissas. Chatten körs serverside via Lovable AI; inga API-nycklar i frontend. Detta kräver ingen separat vektordatabas.

**GitHub.** I repot: all applikationskod, API-klienter, transformationer, databasmigrationer, dokumentation i `docs/`, profilgrafik. Utanför repot: hemligheter och nycklar, hämtad statistik, uppladdade dokument, driftloggar, användardata.

**Begränsningar att känna till.**

- Serverkoden kör i en edge-miljö: inga tunga Node-bibliotek, ingen långvarig process. Excel- och PDF-tolkning måste göras med webbanpassade bibliotek eller styckas upp.
- Enskilda anrop får inte köra hur länge som helst. Stora SCB-hämtningar bör delas per indikator eller per år.
- pg_cron körs i databasen och kan inte nå internet fritt; den anropar vår egen endpoint, som i sin tur pratar med SCB.
- Lovable AI och lagring kostar credits/förbrukning — låg vid denna volym, men kostnadsbilden bör beskrivas innan AI-chatten byggs.
- GDPR: statistik är aggregerad och oproblematisk, men inloggning innebär personuppgifter (e-post) och kräver ställningstagande innan den slås på.

## Robusthet

- Metadatakontrollen är billig och körs alltid; full hämtning bara vid faktisk ändring.
- Varje körning loggas i `data_source_runs` med resultat och felmeddelande.
- Fel vid hämtning lämnar befintlig data orörd — webbplatsen visar alltid senast lyckade data med datum.
- Adminvy visar när varje indikator senast uppdaterades och om någon källa felar.
- Jobbet går att köra manuellt från adminvyn.

## Konkret rekommendation

| Område | Rekommendation |
| --- | --- |
| Databas | Postgres via Lovable Cloud |
| Fillagring | Lovable Cloud Storage (publik + skyddad bucket) |
| Scheduler | pg_cron -> nyckelskyddad endpoint i appen |
| Autentisering | Lovable Cloud Auth + separat `user_roles`-tabell |
| Backendfunktioner | TanStack server functions + server routes i samma repo |
| AI/RAG | Lovable AI + pgvector i samma databas |
| GitHub | All kod, migrationer och dokumentation; inga hemligheter eller data |

## Föreslagen byggordning (kommande iterationer)

1. Aktivera Lovable Cloud, skapa datamodellen och flytta exempelindikatorn dit.
2. SCB-klient + metadatakontroll + full hämtning för **en** indikator, med körningslogg.
3. Schemalagt morgonjobb och en enkel statussida över körningar.
4. Inloggning och roller, därefter dokumentuppladdning.
5. AI-chatt med RAG, efter separat genomgång av kostnad, GDPR och förvaltning.
