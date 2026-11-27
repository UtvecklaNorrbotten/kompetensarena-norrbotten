import { site } from "../config/site";

export type VisualizationExport = {
  title: string;
  subtitle?: string;
  filename: string;
  indicator?: string;
  source: {
    producer: string;
    product?: string;
    identifier?: string;
    url?: string;
    retrieved?: string | null;
  };
  definition?: string;
  unit?: string;
  period?: string | undefined;
  filters?: Record<string, string>;
  notes?: string[];
  legend?: { label: string; color: string; dashed?: boolean }[];
  anchor?: string;
  columns: string[];
  rows: (string | number | null)[][];
};

export function observation(value: number | null | undefined, suppressed = false) {
  if (suppressed) return [null, "Sekretess"] as const;
  if (value == null || !Number.isFinite(value)) return [null, "Uppgift saknas"] as const;
  return [value, "Publicerat"] as const;
}

export function periodRange(periods: string[]) {
  const unique = [...new Set(periods)];
  return unique.length > 1 ? `${unique[0]} – ${unique.at(-1)}` : unique[0];
}

export function exportFilename(indicator: string, selection: string): string {
  return `${indicator}-${selection}`
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9-]+/g, "-")
    .toLowerCase()
    .replace(/^-+|-+$/g, "");
}

export function sourceName(source: VisualizationExport["source"]) {
  return [source.producer, source.product, source.identifier].filter(Boolean).join(" · ");
}

export function filterText(filters: VisualizationExport["filters"] = {}) {
  return Object.entries(filters)
    .map(([key, value]) => `${key}: ${value}`)
    .join(" · ");
}

export function citation(data: VisualizationExport, page: string) {
  const url = new URL(page);
  url.search = "";
  url.hash = data.anchor ?? "";
  return [
    `Källa: ${sourceName(data.source)}. ${data.indicator ?? data.title}.`,
    data.period && `Referensperiod: ${data.period}.`,
    data.source.retrieved && `Uttagsdatum: ${data.source.retrieved.slice(0, 10)}.`,
    data.source.url && `Originalkälla: ${data.source.url}`,
    `Bearbetning och visualisering: ${site.name}. ${url.href}`,
  ]
    .filter(Boolean)
    .join("\n");
}

export function metadataRows(data: VisualizationExport): string[][] {
  return [
    ["Fält", "Uppgift"],
    ["Indikator", data.indicator ?? data.title],
    ["Visualisering", data.title],
    ["Statistikproducent", data.source.producer],
    ["Statistikprodukt", data.source.product ?? ""],
    ["Tabell eller indikator-ID", data.source.identifier ?? ""],
    ["Definition", data.definition ?? ""],
    ["Enhet", data.unit ?? ""],
    ["Referensperiod", data.period ?? ""],
    ...Object.entries(data.filters ?? {}).map(([name, value]) => [`Filter – ${name}`, value]),
    ["Uttagsdatum", data.source.retrieved?.slice(0, 10) ?? ""],
    ["Originalkälla", data.source.url ?? ""],
    ["Bearbetning och visualisering", site.name],
    ...(data.notes ?? []).map((note) => ["Metodanmärkning", note]),
  ];
}

export function downloadBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 60000);
}
