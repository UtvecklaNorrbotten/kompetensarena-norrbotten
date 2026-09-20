# Grafiska resurser

All grafik ligger här – inte utspridd i komponentmappar.

```
src/assets/
  logo/           logotyper (SVG i första hand)
  icons/          ikoner, rena linjeikoner (SVG)
  illustrations/  illustrationer (SVG/WebP)
  figures/        figurer och processvisualiseringar från presentationsmaterialet
  images/         foton och övriga bilder (WebP, annars JPG/PNG)
```

## Riktlinjer

- **Format:** SVG för logotyper, ikoner, figurer och illustrationer. WebP för foton.
  PNG endast när transparens krävs och SVG inte fungerar.
- **Namngivning:** gemener och bindestreck, beskrivande namn,
  t.ex. `kompetensforsorjning-process.svg`.
- **Användning:** importera filen i komponenten
  (`import logo from "@/assets/logo/…svg"`) så att bygget versionshanterar den.
- **public/** används endast för filer som måste ligga på en fast URL
  (favicon, robots.txt).

## Status

Mapparna är avsiktligt nästan tomma. Huvudlogotypen är nu den uppladdade vita
Utveckla Norrbotten-logotypen i Lovables asset-lagring. Figurer från
presentationsmaterialet läggs in när vi valt vilka som ska återanvändas.
