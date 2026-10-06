import type { Database } from "@/integrations/supabase/types";

export type UkaRow = Database["public"]["Tables"]["agg_uka_university"]["Row"];
export type UkaFilters = { gender: string; years: number; dimensions: Record<string, string> };
export const dimensionLabels: Record<string, string> = {
  program: "Yrkesexamensprogram",
  studieform: "Studieform",
  examen: "Examen",
  examenskategori: "Examenskategori",
  inriktning: "Inriktning",
  amnesomrade: "Ämnesområde",
  amnesdelomrade: "Ämnesdelområde",
  amnesgrupp: "Ämnesgrupp",
};
export function dimensions(row: UkaRow): Record<string, string> {
  const values = row.category.split("|");
  return Object.fromEntries(
    row.breakdown ? row.breakdown.split("|").map((key, i) => [key, values[i] ?? ""]) : [],
  );
}
export function periodOrder(period: string): number {
  const year = Number(period.match(/\d{4}/)?.[0] ?? 0);
  return year * 10 + (period.startsWith("HT") ? 2 : period.startsWith("VT") ? 1 : 0);
}
export function periodLabel(period: string): string {
  return period.replace(/^(HT|VT)(\d)/, "$1 $2");
}

/** Välj källans exakta projektion. Summera aldrig totaler, kön eller hierarkinivåer. */
export function selectUkaRows(
  rows: UkaRow[],
  filters: UkaFilters,
  detail = false,
): { rows: UkaRow[]; breakdown: string; applied: string[]; ambiguous: boolean } {
  const available = new Set(rows.flatMap((r) => (r.breakdown ? r.breakdown.split("|") : [])));
  const selected = Object.entries(filters.dimensions).filter(([k, v]) => v && available.has(k));
  const keys = selected.map(([k]) => k);
  const breakdowns = [...new Set(rows.map((r) => r.breakdown))].sort(
    (a, b) => (a ? a.split("|").length : 0) - (b ? b.split("|").length : 0) || a.localeCompare(b),
  );
  const target = breakdowns.find(
    (b) => keys.every((key) => b.split("|").includes(key)) && (!detail || b !== ""),
  );
  if (target === undefined) return { rows: [], breakdown: "", applied: keys, ambiguous: false };
  const candidate = rows.filter(
    (r) => r.breakdown === target && selected.every(([key, value]) => dimensions(r)[key] === value),
  );
  const periods = [...new Set(rows.map((r) => r.period))].sort(
    (a, b) => periodOrder(a) - periodOrder(b),
  );
  const isSemester = periods.some((period) => /^(HT|VT)/.test(period));
  const recent = new Set(periods.slice(-(filters.years * (isSemester ? 2 : 1))));
  const filtered = candidate.filter((r) => recent.has(r.period));
  const overview = filtered.filter((r) => r.gender === filters.gender);
  const seen = new Set<string>();
  const ambiguous =
    !detail &&
    overview.some((r) => {
      const key = `${r.period}|${r.gender}`;
      if (seen.has(key)) return true;
      seen.add(key);
      return false;
    });
  return { rows: ambiguous ? [] : filtered, breakdown: target, applied: keys, ambiguous };
}

export function dimensionOptions(
  rows: UkaRow[],
  filters: Record<string, string>,
): Record<string, string[]> {
  const result: Record<string, Set<string>> = {};
  for (const row of rows) {
    const d = dimensions(row);
    for (const [key, value] of Object.entries(d)) {
      if (!Object.entries(filters).every(([k, v]) => !v || k === key || !(k in d) || d[k] === v))
        continue;
      (result[key] ??= new Set()).add(value);
    }
  }
  return Object.fromEntries(
    Object.entries(result).map(([key, values]) => [
      key,
      [...values].sort((a, b) => a.localeCompare(b, "sv")),
    ]),
  );
}

/** Visa kön samtidigt. Saknat könsvärde blir en lucka, aldrig en beräknad nolla. */
export function ukaGenderSeries(rows: UkaRow[]): string[] {
  return rows.some((row) => row.gender === "Kvinnor" || row.gender === "Män")
    ? ["Kvinnor", "Män", ...(rows.some((row) => row.gender === "Total") ? ["Total"] : [])]
    : ["Total"];
}

export function ukaGenderTimeline(rows: UkaRow[], series: string[]) {
  const periods = [...new Set(rows.map((row) => row.period))].sort(
    (a, b) => periodOrder(a) - periodOrder(b),
  );
  return periods.map((period) => {
    const point: Record<string, string | number | null> = { period: periodLabel(period) };
    for (const gender of series) {
      const matches = rows.filter((row) => row.period === period && row.gender === gender);
      point[gender] = matches.length === 1 ? matches[0]!.value : null;
    }
    return point;
  });
}

export function formatUkaValue(value: number | null | undefined, unit: string): string {
  if (value == null) return "Uppgift saknas";
  const ratio = unit === "sökande per antagen";
  return `${new Intl.NumberFormat("sv-SE", { minimumFractionDigits: ratio ? 1 : 0, maximumFractionDigits: unit === "antal" ? 0 : 1 }).format(value)}${unit === "%" ? " %" : ""}`;
}

/** Kalenderår för terminer, källans periodetikett för års-/läsårsdata. */
export function ukaDetailPeriods(rows: UkaRow[], requestedYear = "", term = "all") {
  const periods = [...new Set(rows.map((r) => r.period))].sort(
    (a, b) => periodOrder(a) - periodOrder(b),
  );
  const semester = periods.some((p) => /^(HT|VT)\d{4}$/.test(p));
  const yearOf = (p: string) => (semester ? p.slice(2) : p);
  const years = [...new Set(periods.map(yearOf))].reverse();
  const complete = years.find((y) => periods.includes(`VT${y}`) && periods.includes(`HT${y}`));
  const year = years.includes(requestedYear) ? requestedYear : (complete ?? years[0] ?? "");
  const chosen = periods.filter(
    (p) => yearOf(p) === year && (!semester || term === "all" || p.startsWith(term)),
  );
  return {
    semester,
    years,
    year,
    periods: chosen,
    rows: rows.filter((r) => chosen.includes(r.period)),
  };
}
