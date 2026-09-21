# Konfigurera GitHub Actions-secrets för ETL

Inga kodändringar. Detta är en instruktion plus en kort verifiering som jag kör åt dig efteråt.

## 1. ETL_BASE_URL

Projektet är inte publicerat ännu, så det finns två giltiga basadresser:

- Förhandsvisning (fungerar nu, alltid senaste bygget):
  `https://project--8b37a852-2c3d-45d9-8ad2-8914df989866-dev.lovable.app`
- Produktion (börjar svara först när du publicerat projektet):
  `https://project--8b37a852-2c3d-45d9-8ad2-8914df989866.lovable.app`

Båda adresserna är stabila och ändras inte om projektet byter namn. Ingen avslutande snedstreck.

Rekommendation: sätt `ETL_BASE_URL` till dev-adressen nu för att kunna provköra flödet, och byt till produktionsadressen när webbplatsen är publicerad.

## 2. Rotera ETL_PUBLISH_KEY

Nyckeln måste vara identisk på två ställen och måste därför skapas av dig — ett värde som genereras inne i Lovable kan aldrig visas igen och går alltså inte att klistra in i GitHub.

1. Skapa ett slumpvärde lokalt, till exempel i terminalen:
   `openssl rand -hex 32`
   (Alternativ: en lösenordshanterare som genererar 64 slumpmässiga tecken.)
2. Spara värdet i Lovable: jag öppnar ett säkert formulär för `ETL_PUBLISH_KEY` där du klistrar in det. Formuläret ersätter det gamla värdet.
3. Spara samma värde i GitHub: repo `UtvecklaNorrbotten/kompetensarena-norrbotten` → Settings → Secrets and variables → Actions → New repository secret → namn `ETL_PUBLISH_KEY`, värdet inklistrat.
4. Lägg till `ETL_BASE_URL` på samma ställe som en egen secret.
5. Radera värdet ur urklipp/terminalhistorik. Efter steg 2–3 finns det bara i Lovable och GitHub, och kan inte läsas ut igen från något av ställena.

Ingen befintlig hemlighet visas, och det nya värdet skrivs aldrig in i repot, i koden eller i något svar från mig.

### Överlappning vid byte (valfritt)
Om ett ETL-jobb kan vara igång under bytet kan den gamla nyckeln tillfälligt sparas som `ETL_PUBLISH_KEY_PREVIOUS` i Lovable — men eftersom det gamla värdet inte går att läsa ut är det inte möjligt här. Byt i stället när inget jobb körs.

## 3. Verifiering (jag gör detta efter att du sparat)

- Bekräftar att båda secret-namnen nu finns i GitHub-repot (endast namn, aldrig värden).
- Bekräftar att `ETL_PUBLISH_KEY` finns som Lovable-secret.
- Bekräftar i koden att alla ETL-endpoints läser samma nyckel: `src/lib/etl-auth.server.ts` är den enda platsen som läser `ETL_PUBLISH_KEY`, och den används av `publish-indicator`, `etl-batch/start|chunk|finalize|abort`, `etl-state` och `etl-no-change`.
- Kör ett ofarligt anrop mot `GET /api/public/jobs/etl-state?indicator_id=e3-matchning-utbildning` från GitHub Actions (manuell körning av arbetsflödet, eller så bekräftar du att första riktiga körningen svarar 200 i stället för 401/403). Jag kan inte testa med din nyckel själv eftersom värdet inte går att läsa ut.

## Teknisk notering

`R/etl/etl_api.R` läser `ETL_BASE_URL` och `ETL_PUBLISH_KEY` ur miljön och arbetsflödet `.github/workflows/etl-e3-tab6929.yml` skickar in dem som secrets. Inget behöver ändras i dessa filer.
