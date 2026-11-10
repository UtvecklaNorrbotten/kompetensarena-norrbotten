# Felunderlag till UKÄ: CSV-export returnerar nollbytefiler

Förberett 2026-11-06. **Inte skickat.**

Föreslagen mottagare: Analysavdelningen, `analys@uka.se`.
Kontaktadressen anges i UKÄ:s [kvalitetsdeklaration](https://www.uka.se/download/18.608782d21876ee45b1e28e/1681220506899/UF0204_kd_2022.pdf).

## Meddelande

Ämne: Högskolan i siffror – minimala HST-exporter ger CSV-filer på 0 byte

Hej!

Vi arbetar med att hämta statistik till Kompetensarena Norrbotten och behöver hjälp med CSV-exporten i Högskolan i siffror.

Den 6 november 2026 gav följande små uttag filer på 0 byte även när vi använde ert ordinarie webbgränssnitt:

1. Öppna https://statistik-www.uka.se/export/?indicator=33.
2. Välj HST per studieform och ämnesgrupp, indikator 33.
3. Välj Från och Till 2025/26, lärosäte Riket.
4. Avmarkera Kvinnor och Män och välj Totala värdet för kön.
5. Behåll Totala värdet för ålder, studieform och ämnesområde.
6. Klicka Ladda ner dataset.

Resultat: `2026-11-06-173736d9702a_33.csv`, **0 byte**, inte ens CSV-rubriker.
Ett andra uttag med Från och Till 2024/25 gav `2026-11-06-3fee596c0240_33.csv`, också **0 byte**.
Det andra periodurvalet skickades först via webbgränssnittet i vår undersökning.

Vi kan reproducera det första resultatet med export-API:t:

```python
import requests

filters = [
    "from:2025/26", "to:2025/26", "uni:1",
    "gender:Total", "age:1",
    "6.dynamic:TOTAL", "7.dynamic:TOTAL",
]
response = requests.post(
    "https://statistik-www.uka.se/export/api/index.php",
    data=[("indicator", "33")] + [("filters[]", v) for v in filters],
    timeout=60,
)
response.raise_for_status()
url = response.json()["fileUrl"]
download = requests.get(url, timeout=60)
print(url, download.status_code, len(download.content))
```

Resultat för det första uttaget: HTTP 200 och en fil-URL till samma cachefil som webbgränssnittet laddar ner. Nedladdningen svarar också HTTP 200 men innehåller 0 byte.
Vår befintliga R-klient ger samma tomma resultat.

Samtidigt returnerar JSON-API:t data:

- https://statistik-api.uka.se/api/totals/33?university=1&year=2025%2F26 ger källtotalen **341 246,6 HST** för 2025/26.
- https://statistik-api.uka.se/api/totals/33?university=1&year=2024%2F25 ger källtotalen **341 995,2 HST** för 2024/25.

Vi ser samma nollbyteproblem för minimala CSV-kontroller av indikatorerna 13, 31, 33, 97, 99, 108, 136, 77, 134 och 135. Detta är alltså inte enbart ett stort HST-uttag. Vi tolkar inte tomma filer som att statistik saknas.

Kan ni hjälpa oss att kontrollera:

1. Om exporttjänsten har ett aktuellt drift- eller cacheproblem, och hur redan skapade tomma cachefiler ska hanteras?
2. Om anropet ovan behöver någon annan dokumenterad parameter eller header?
3. Vilken hämtningsväg ni rekommenderar för fullständiga, återstartbara uttag med historik och alla dimensioner?
4. Om `/api/totals/` och dess kombinerade `group_slug`-länkar är avsedda för automatiserad hämtning, vilka begränsningar som gäller samt hur en källversion/revision kan identifieras?
5. Om det finns ett bulkuttag som bevarar källtotaler och alla hierarkinivåer utan många små API-anrop?

Vi har stoppat produktionsimporten från dessa tester tills vi kan verifiera fullständigheten. Inga totaler beräknas genom att summera delgrupper.

## Tekniskt underlag

### Ytterligare verifierat problem i JSON-alternativet

Exportfiltren återanvänder koden 1051 (Övrigt) under både 914 (Medicin och odontologi)
och 915 (Naturvetenskap): `dynamic:1051_914` och `dynamic:1051_915`.
För Riket, 2025/26, Kvinnor, age_group=8 listar följande medicinska delområdesnod
dubbla studieformsetiketter med olika värden och olika gruppsluggar:

https://statistik-api.uka.se/api/totals/33?university=1&year=2025%2F26&group_slug=1806cec79a532daca1ef3c627f5681b8ad995441&gender=Kvinnor&age_group=8

- Fristående kurser, **38,1**: slug `12ab49225797148f21812a058af4630b755930ae`. Barnanropet visar Biomedicinsk laboratorievetenskap, Medicinska tekniker och Övrigt inom medicin.
- Fristående kurser, **56,2**: slug `fdc158ac61cb17a0bbdbcd363ba99577f4048990`. Barnanropet visar Husdjursvetenskap, Livsmedelsvetenskap och Övrigt inom naturvetenskap.

Även Generella program och Yrkesexamensprogram förekommer dubbelt i detta svar.
Kan ni bekräfta hur föräldrakontexten ska bevaras och vilka kombinerade sluggar som hör till respektive område?
Vi har stoppat denna JSON-hämtning vid konflikten. Koppling till CSV-felet är ännu inte fastställd.
Exakta observationer och länkar finns i `uka-source-context-conflict-2026-11-06.json`.

- Reproducerbara GitHub-kontroller: https://github.com/UtvecklaNorrbotten/kompetensarena-norrbotten/actions/runs/42185017866.
- `uka-web-control-2026-11-06.json`: webbens valda filter, nedladdade filnamn, filstorlekar och kontrollsummor.
- `uka-source-control-2026-11-06.json`: kontrollresultat per indikator.
- `uka-web-control-2026-11-06.jpg`: webbens totalval.

Begränsning: vi har jämfört DOM-urval, webbens publicerade formulärserialisering och faktiskt nedladdade filnamn. Vi har inte fångat råa HTTP-requestbytes från webbläsaren. Den interna orsaken till de tomma filerna och eventuell cachepåverkan behöver därför verifieras hos UKÄ.


## Ytterligare diagnostik: frånvarande kombinationer ger HTTP 500

Två direktanrop med universitet=32 (LTU), 2025/26, Kvinnor, age_group=8,
Fristående kurser och Övrigt gav HTTP 500 för båda kända nationella sluggarna
`12ab49225797148f21812a058af4630b755930ae` och
`fdc158ac61cb17a0bbdbcd363ba99577f4048990`.
Dessa Övrigt-rader annonserades inte i LTU:s motsvarande ämnesområden.
Det är därför inte fastställt om urvalet saknar observationer eller om servern har ett annat fel.
Vilken dokumenterad respons ska betyda ett legitimt tomt urval?
Se `uka-absent-selection-probe-2026-11-06.json`. Underlaget är fortfarande inte skickat.
