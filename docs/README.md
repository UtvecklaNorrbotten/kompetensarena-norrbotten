# Dokumentation för Kompetensarena Norrbotten

Här samlas vägledning för den som ska utveckla eller vidareförvalta plattformen. Källkoden ligger i `src/` och följer strukturen i rot-README:n.

## Snabböversikt

- **Syfte:** Kunskaps- och analysportal för kompetensförsörjning i Norrbotten.
- **Stack:** TanStack Start (React 19 + Vite), Tailwind CSS v4, Recharts.
- **Innehåll just nu:** Visuell och teknisk grund — färger, typografi, navigation, layout, ett statistikexempel.
- **Nästa steg:** fastställa informationsarkitektur, byta ut placeholder-menyn, lägga in riktig logotyp och figurer, definiera de första riktiga indikatorerna.

## Dokument i denna mapp

| Fil | Vad den beskriver |
| --- | --- |
| `README.md` | Denna översikt. |
| `komponenter.md` | Katalog över återanvändbara komponenter: layout, ui och charts. |
| `utveckla.md` | Kom igång lokalt, konventioner och GitHub-arbetsflöde. |

## Var viktiga saker finns

- **Designsystem:** `src/styles.css` — alla färger, typografi, spacing, radier och fokusmarkeringar.
- **Meny:** `src/config/navigation.ts` — placeholder-menyn som enkelt byts ut.
- **Sidinställningar:** `src/config/site.ts` — namn, tagline, kontaktmail.
- **Data och indikatorer:** `src/lib/indicators.ts` (datalager) och `src/data/` (typer + exempeldata).
- **Sidor:** `src/routes/` — filbaserad routing för TanStack Start.
- **Grafik:** `src/assets/` — logotyp, ikoner, illustrationer, figurer och bilder.

## Tillfälligt innehåll

Följande är platshållare och ska bytas ut i kommande iterationer:

- Logotypen i `src/assets/logo/kompetensarena-placeholder.svg`.
- Menystrukturen i `src/config/navigation.ts`.
- Exempelindikatorn i `src/data/example-indicators.ts`.
- Sidan `/kommer-senare` som fångar upp ännu obyggda menyposter.

## Designfilosofi

- Luftigt och avskalat uttryck, anpassat för offentlig verksamhet.
- Mörkgrön och ljusgrön som dominerande ytor, orange som begränsad accent.
- Ingen text i orange eller ljusgrön mot ljus bakgrund — tillräckliga kontraster.
- Tydliga fokusmarkeringar och tangentbordsnavigering.
