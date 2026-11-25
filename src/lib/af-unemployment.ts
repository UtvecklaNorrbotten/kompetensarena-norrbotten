export type AfValue = number | null | "<5";
export type AfPair = [
  period: string,
  group: string,
  sex: string,
  unemployed: AfValue,
  workforce: AfValue,
];
export type AfHistory = [
  period: string,
  sex: string,
  total: AfValue,
  open: AfValue,
  program: AfValue,
];
export type AfGeoData = { pairs: AfPair[]; history: AfHistory[] };
export type AfPoint = {
  period: string;
  count: number | null;
  rate: number | null;
  open: number | null;
  program: number | null;
  suppressed: boolean;
};
export const afGroups: Record<string, string> = {
  total: "Samtliga",
  young: "Unga 18–24 år",
  older: "Äldre (AF:s åldersgrupp)",
  domestic: "Inrikes födda",
  foreign: "Utrikes födda",
  pre: "Förgymnasial utbildning",
  upper: "Gymnasial utbildning",
  post: "Eftergymnasial utbildning",
};
export const afNumber = (v: AfValue | undefined, digits = 0): string =>
  v === "<5"
    ? "Sekretess"
    : typeof v === "number" && Number.isFinite(v)
      ? v.toLocaleString("sv-SE", { maximumFractionDigits: digits, minimumFractionDigits: digits })
      : "Uppgift saknas";
export function afRate(n: AfValue | undefined, d: AfValue | undefined): number | null {
  return typeof n === "number" && typeof d === "number" && d > 0 ? (n / d) * 100 : null;
}
export function monthOffset(period: string, offset: number): string {
  const [year, month] = period.split("-").map(Number);
  const date = new Date(Date.UTC(year!, month! - 1 + offset, 1));
  return date.toISOString().slice(0, 7);
}
export function afSeries(data: AfGeoData, group: string, sex: string): AfPoint[] {
  const pairs = new Map(
    data.pairs.filter((r) => r[1] === group && r[2] === sex).map((r) => [r[0], r]),
  );
  const history = new Map(data.history.filter((r) => r[1] === sex).map((r) => [r[0], r]));
  const periods = [
    ...new Set([...pairs.keys(), ...(group === "total" ? history.keys() : [])]),
  ].sort();
  if (!periods.length) return [];
  // Explicit gaps: a missing month must never be connected or used as a rolling window.
  const result: AfPoint[] = [];
  for (let p = periods[0]!; p <= periods.at(-1)!; p = monthOffset(p, 1)) {
    const pair = pairs.get(p),
      h = history.get(p);
    const n = pair ? pair[3] : group === "total" ? h?.[2] : null;
    result.push({
      period: p,
      count: typeof n === "number" ? n : null,
      rate: afRate(pair?.[3], pair?.[4]),
      open: typeof h?.[3] === "number" ? h[3] : null,
      program: typeof h?.[4] === "number" ? h[4] : null,
      suppressed: n === "<5" || pair?.[4] === "<5",
    });
  }
  return result;
}
export function rollingAf(points: AfPoint[]): AfPoint[] {
  return points.map((point, i) => {
    const window = points.slice(Math.max(0, i - 11), i + 1);
    const average = (key: "count" | "rate" | "open" | "program") =>
      window.length === 12 &&
      window.every((p, j) => p[key] !== null && p.period === monthOffset(point.period, j - 11))
        ? window.reduce((sum, p) => sum + p[key]!, 0) / 12
        : null;
    return {
      ...point,
      count: average("count"),
      rate: average("rate"),
      open: average("open"),
      program: average("program"),
      suppressed: window.some((p) => p.suppressed),
    };
  });
}
export function afChange(points: AfPoint[], period: string, key: "count" | "rate") {
  const current = points.find((p) => p.period === period)?.[key];
  const before = points.find((p) => p.period === monthOffset(period, -12))?.[key];
  return current != null && before != null ? current - before : null;
}
