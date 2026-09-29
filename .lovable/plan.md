# Undersidor, vänstermeny, sök och enkätdata (Kompetensarena)

## Nuläge och nästa steg (efter din statusrapport)
Enligt din rapport är steg 1 och 2 byggda: områdessidor, vänstermeny, sökdialog, sökmigration och AGENTS.md. De ändringarna finns dock inte i den här projektkopian än. Här syns inga områdessidor och ingen sökmigration, så de ligger troligen bara lokalt eller på GitHub. Nästa steg är därför:
1. Hämta in senaste main från GitHub. Om ändringarna inte ligger där behöver du pusha dem först.
2. Kör sökmigrationen i Lovable Cloud exakt som den står i filen. Kontrollera sedan tabell, index och behörigheter samt att en provsökning svarar.
3. Indexera fullständiga sidtexter, indikatorer samt SSYK-, SNI- och kommunposter så att sökningen hittar dem.
4. Planen ändras så att den beskriver den egenbyggda menyn i stället för shadcn Sidebar.
5. Kontrollera i webbläsaren att menyn, sökningen och översiktssidorna fungerar.

Väntar på dig:
- Ett representativt exempel på den kodade enkätfilen, som behövs för steg 3.
- Exakta åtkomstregler för kommunanvändare och ledning, som behövs för steg 4.


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

## Steg 4 – Behörighet för arbetsgivarnivå
- Nya roller, "kommunanvändare" och "ledning", som admin tilldelar manuellt beroende på vem materialet delas med. Rollerna kan få olika åtkomst.
- Offentliga sidor visar sammanställningar per bransch, yrke och geografi. Vid varje siffra står underlaget, till exempel "baserat på 12 arbetsgivare, 48 svar". Arbetsgivare är ett bredare ord än företag eftersom även myndigheter och organisationer har svarat.
- Svar per arbetsgivare visas bara för admin, kommunanvändare och ledning. Skyddet ligger i databasen och på servern, inte bara i gränssnittet.

## Frågor att klara ut innan steg 3
- Rådata finns: en rad per svar och svarande, plus ett antal kolumner. Vi väljer ut de relevanta kolumnerna, och resten av enkätlogiken filtreras bort vid import. Ett exempel på filen behövs för att göra kolumnmappningen.
- SSYK- och SNI-kodning är till stor del redan gjord lokalt. Den kodade filen importeras direkt, så ingen fritextmatchning behövs i portalen.
- Personuppgiftsbiträdesavtal och laglig grund finns redan. Det som återstår är att bestämma om personuppgifter, till exempel kontaktpersoner, ska visas i portalen. Tills det är bestämt importeras de inte.

## Tekniska detaljer
- Menyn är egenbyggd (inte shadcn Sidebar). Utfällning vid hover/fokus styrs med en kort fördröjning. Konfigurationen ligger i `src/config/areas.ts` så att ingen menytext hårdkodas.
- Routerna `omraden.$area.index.tsx` och `omraden.$area.$topic.tsx` hämtar innehåll från konfigurationen och får var sin `head()`.
- Sök: tabellen `search_index` med `tsvector('swedish')` och en publik serverfunktion som returnerar högst 20 träffar.
- Enkättabellerna `survey_*` får RLS. Aggregat hämtas via vyer eller funktioner med ett minsta antal (k), och rå data kräver `has_role(admin|analytiker)`.
- Arkitekturreglerna läggs till i AGENTS.md.

Förslag: vi börjar med steg 1–2 och tar steg 3 när vi har ett exempel på enkätfilen.
