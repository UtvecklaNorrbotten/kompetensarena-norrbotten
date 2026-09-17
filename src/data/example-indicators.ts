import type { Indicator } from "./types";

/**
 * EXEMPELDATA — påhittade siffror, endast för att visa komponenternas form.
 * Ersätts senare av riktiga datakällor via src/lib/indicators.ts.
 */
export const exampleIndicators: Indicator[] = [
  {
    id: "exempel-arbetsloshet",
    name: "Arbetslöshet (exempel)",
    description:
      "Andel av befolkningen 16–64 år som är inskriven som arbetslös. Serien nedan är påhittad och används endast för att visa hur en indikator presenteras.",
    unit: "procent",
    metadata: {
      source: "Exempelkälla",
      updatedAt: "2026-09-01",
      geoLevel: "län",
      area: "Norrbottens län",
      period: "2017–2026",
      isExample: true,
    },
    series: [
      { label: "2017", value: 6.8 },
      { label: "2018", value: 6.5 },
      { label: "2019", value: 6.4 },
      { label: "2020", value: 7.9 },
      { label: "2021", value: 7.2 },
      { label: "2022", value: 6.3 },
      { label: "2023", value: 6.1 },
      { label: "2024", value: 5.9 },
      { label: "2025", value: 5.7 },
      { label: "2026", value: 5.6 },
    ],
  },
];
