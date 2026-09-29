# Undersidor, vänstermeny, sök och enkätdata (Kompetensarena)

## Mål
- En smal vänstermeny med områden. Klick på ett område leder till områdets Översikt, därifrån kan man gå vidare till fördjupningar.
- Sök på hela webbplatsen.
- Enkätsvaren från Kompetensarena Norrbotten kombineras med SCB, AF m.fl. för att visa var behoven är mest akuta, både i antal och i andel, och hur läget ser ut framåt (pensionsavgångar, åldrande befolkning).
- Ett inloggat läge där behöriga personer kan se enskilda företags svar.

## Steg 1 – Struktur och meny (exempeldata)
**Områden:** Yrken, Branscher, Län/Kommun, Utbildning, Kompetenser. Under dem finns en grupp "Data och metod" (Om, Ladda ned data).

**Sidor per område:**
```text
/omraden/yrken                -> Översikt
/omraden/yrken/rekryteringsbehov
/omraden/yrken/pensionsavgangar
... (samma mönster för varje område)
```
Fördjupningarna i varje område börjar som platshållare och är tydligt märkta.

**Vänstermenyn:**
- Hopfälld är den bara en smal ikonlist (ca 56 px). När man hovrar eller flyttar fokus dit fälls den ut över innehållet (ca 220 px) utan att innehållet flyttar på sig. Det blir smalare än i exemplet.
- Den är ett träd: aktivt område visas utfällt med sina undersidor, och aktuell sida markeras.
- Den fungerar med tangentbord och skärmläsare, och går att låsa i utfällt läge.
- På mobil öppnas menyn som en panel från vänster.
- Ingen andra kolumn med filter som i exemplet. Val av region, yrke och liknande ligger i stället överst på varje sida.

## Steg 2 – Sök
- En sökruta i sidhuvudet som också öppnas med kortkommandot Ctrl/Cmd+K.
- Sökningen täcker sidor och texter, indikatorer samt yrken, branscher och kommuner.
- Den körs i vår egen databas med svensk fulltextsökning. Ingen extern tjänst behövs.

## Steg 3 – Enkätdata (Kompetensarena-kartläggningen)
**Import:** I adminvyn laddar man upp en Excel- eller CSV-fil. Filen kontrolleras först och visas som förhandsgranskning. Därefter publiceras den i ett svep, så att tidigare data ligger kvar om något går fel.

**Innehåll som lagras:**
- Företag: namn, organisationsnummer, kommun, bransch (SNI) och antal anställda.
- Rekryteringsbehov per yrkesroll: antal per anställningsform (tillsvidare, säsong, semestervikariat, annat), krav på utbildningsnivå, erfarenhet, körkort och språk.
- Behov av kompetensutveckling: område, antal medarbetare, förslag på tema och typ av utbildningsinsats.
- Intresse av att ta emot studerande, möjlighet att rekrytera engelskspråkig personal och vilket stöd som behövs, samt önskad samverkan med skolor.

**Koppling till SCB och AF:** Yrken kopplas via SSYK-koder, branscher via SNI-koder och geografi via kommunkoder. Det gör det möjligt att räkna andelar, till exempel behov i förhållande till antal sysselsatta, och att lägga till åldersstruktur och pensionsavgångar.

## Steg 4 – Behörighet för företagsnivå
- En ny roll, "analytiker", som admin tilldelar manuellt.
- Offentliga sidor visar bara sammanställda siffror. Grupper med färre än cirka 3–5 företag döljs så att enskilda företag inte kan pekas ut.
- Svar per företag visas bara för admin och analytiker. Skyddet ligger i databasen och på servern, inte bara i gränssnittet.

## Frågor att klara ut innan steg 3
- Hur ser enkätexporten ut? Ett exempel på filen eller en kolumnlista behövs.
- Finns SSYK- och SNI-koder i svaren, eller behöver vi matcha fritext mot koder?
- Personuppgiftsbiträdesavtal och laglig grund för att lagra företagssvar, eftersom kontaktpersoner kan förekomma.

## Tekniska detaljer
- Menyn byggs på shadcn Sidebar med `collapsible="icon"` och variant `floating`. Utfällning vid hover/fokus styrs med en kort fördröjning. Konfigurationen ligger i `src/config/areas.ts` så att ingen menytext hårdkodas.
- Routerna `omraden.$area.index.tsx` och `omraden.$area.$topic.tsx` hämtar innehåll från konfigurationen och får var sin `head()`.
- Sök: tabellen `search_index` med `tsvector('swedish')` och en publik serverfunktion som returnerar högst 20 träffar.
- Enkättabellerna `survey_*` får RLS. Aggregat hämtas via vyer eller funktioner med ett minsta antal (k), och rå data kräver `has_role(admin|analytiker)`.
- Arkitekturreglerna läggs till i AGENTS.md.

Förslag: vi börjar med steg 1–2 och tar steg 3 när vi har ett exempel på enkätfilen.
