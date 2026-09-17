/**
 * Gemensamma datatyper för indikatorer och tidsserier.
 *
 * Tanken är att all statistik i plattformen beskrivs på samma sätt:
 * en indikator = metadata + datapunkter. Visualiseringskomponenterna tar
 * emot dessa typer och vet inget om var data kommer ifrån.
 */

/** Geografisk nivå som en indikator redovisas på. */
export type GeoLevel = "riket" | "län" | "kommun";

export type IndicatorMetadata = {
  /** Datakälla, t.ex. "SCB" eller "Arbetsförmedlingen". */
  source: string;
  /** ISO-datum (YYYY-MM-DD) för senaste uppdatering. */
  updatedAt: string;
  geoLevel: GeoLevel;
  /** Geografiskt område, t.ex. "Norrbottens län". */
  area: string;
  /** Period som serien täcker, t.ex. "2015–2024". */
  period: string;
  /** Sant om innehållet är påhittad exempeldata. */
  isExample?: boolean;
};

export type TimeSeriesPoint = {
  /** Etikett på x-axeln, t.ex. ett årtal. */
  label: string;
  value: number;
};

export type Indicator = {
  id: string;
  name: string;
  description: string;
  /** Enhet, t.ex. "procent" eller "antal personer". */
  unit: string;
  metadata: IndicatorMetadata;
  series: TimeSeriesPoint[];
};
