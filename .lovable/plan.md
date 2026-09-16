# Kompetensarena Norrbotten — iteration 1: visuell och teknisk grund

Målet med denna iteration är en liten, genomarbetad grund: grafisk profil, header med
hovernavigation, responsiv layout, ett fåtal sidor och en enda enkel visualisering.
Inga externa tjänster, ingen databas, ingen inloggning, ingen AI.

## Vad som byggs nu

**Grafisk profil som designsystem**
- Färgpaletten (mörkgrön #487629, grön #92CC6B, ljusgrön #E6F3DE, orange #F5C55C,
  ljusorange #FBEBC6, text #333333, neutral #EEF0EC, bakgrund #F8F9F6, vit) läggs in
  som namngivna designvärden ett enda ställe och används överallt via semantiska namn
  (bakgrund, yta, text, accent, ram, fokus).
- Typografi: Titillium Web för rubriker, Roboto/Roboto Light för brödtext, laddas i
  sidhuvudet. Responsiv rubrikskala.
- Designvärden även för spacing, radier, maxbredd på innehåll samt hover-, focus- och
  active-states.
- Tillgänglighet: orange och ljusgrön används som ytor/accenter, aldrig som textfärg mot
  ljus bakgrund. Mörkgrön text kontrollerad mot ljusa ytor. Synlig fokusram överallt.

**Sidram (layout)**
- Header med logotypsplats, huvudnavigation och en enkel sidfot.
- Generösa ytor, luft, avskalat uttryck; enstaka cirkel/geometriskt element som accent.
- Gemensam innehållsbredd och sektionskomponenter så att nya sidor ser likadana ut.

**Navigation (kärnan i iterationen)**
- Desktop: huvudmeny där undermeny öppnas vid hover **och** vid klick, med fördröjd
  stängning så att musen hinner in i panelen.
- Fullt tangentbordsstöd: Tab, Enter/Space, piltangenter, Escape stänger, fokus förs
  tillbaka till huvudposten. Korrekt aria-attribut och semantisk markup.
- Touch: första tryck öppnar undermeny, andra tryck navigerar (ingen hover-fälla).
- Mobil: hamburgermeny med panel över hela skärmen och utfällbara undermenyer,
  fokuslås och Escape.
- Menyinnehållet (rubriker/poster) ligger i **en separat konfigurationsfil** som
  placeholder och kan bytas ut utan att röra komponentkoden.

**Sidor (avsiktligt få)**
- Startsida: kort hero, kort introduktion, en sektion som visar formspråket.
- En innehållssida ("Om Kompetensarena") som visar typografi och textlayout.
- En exempelsida för statistik med **en** enkel visualisering.
- Övriga menyposter pekar mot en gemensam "Kommer senare"-sida så att inga trasiga
  länkar uppstår.

**Ett minimalt statistikexempel**
- Ett tidsseriediagram eller stapeldiagram med ~10 påhittade värden, tydligt märkt
  "Exempeldata".
- Runt diagrammet visas mönstret för framtiden: rubrik, kort beskrivning, samt
  metadatarad (källa, senast uppdaterad, geografisk nivå, period).
- Diagramkomponenten tar emot data och metadata som indata — inget hårdkodat i UI:t.

**Data- och kodstruktur (förberedelse, inte överbyggnad)**
- Exempeldata ligger i en datamapp, inte i komponenterna.
- Enkla typer för indikator, tidsserie och metadata definieras en gång.
- Ett tunt datalager (funktion som hämtar en indikator) så att källan senare kan bytas
  från lokal fil till API utan att sidorna ändras.

**Assetstruktur**
- Tydliga mappar för logotyper, ikoner, illustrationer, figurer och bilder, med en kort
  README som förklarar var saker ska läggas och vilka format som gäller.
- Mapparna skapas tomma (endast en platshållarlogotyp), inget exempelmaterial.
- Logotypen behandlas som grafisk resurs, inte som text.

**Dokumentation för GitHub-arbete**
- README uppdateras: syfte, teknisk stack, katalogstruktur, hur designsystemet fungerar,
  var menyn konfigureras, vad som är placeholder och vad som är nästa steg.
- Koden delas i små, namngivna komponenter — inga stora monolitiska filer.

## Vad som uttryckligen väntar

Databas, inloggning och behörigheter, filuppladdning, externa API:er och datakällor,
AI-sammanfattningar och chatt, kartor, filter, export, webbstatistik, fullständig
informationsarkitektur, återskapande av figurer från presentationen, samt större
mängder innehåll och exempeldata.

## Tekniskt

- Stack: TanStack Start (React + Vite) med Tailwind, redan i projektet. Inga nya
  ramverk.
- Enda nya beroende: ett diagrambibliotek (Recharts) för exempeldiagrammet.
- Föreslagen struktur:

```text
src/
  routes/            sidor (start, om, statistik-exempel, kommer-senare)
  components/
    layout/          header, nav (desktop + mobil), footer, sektioner
    ui/              knapp, kort, metadatarad m.m.
    charts/          diagramkomponent(er)
  config/            navigation.ts (placeholder-meny), site.ts
  data/              exempeldata + typer
  lib/               datahämtning, hjälpfunktioner
  assets/
    logo/ icons/ illustrations/ figures/ images/  (+ README)
  styles.css         designtokens
```

- Inlåsning: inget Lovable-specifikt i koden; allt är vanlig React/Vite och kan klonas,
  byggas och vidareutvecklas via GitHub. Diagrambiblioteket är utbytbart eftersom
  diagrammet kapslas i en egen komponent.

## Nästa steg efter iteration 1

1. Fastställa informationsarkitektur och byta ut placeholder-menyn.
2. Välja och lägga in riktiga figurer, ikoner och illustrationer från presentationen.
3. Definiera de första riktiga indikatorerna och deras datamodell.
4. Först därefter diskutera behov av databas, inloggning, AI och webbstatistik — med
   beskrivning av alternativ, kostnad, GDPR och förvaltning innan något implementeras.
