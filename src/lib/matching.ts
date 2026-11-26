export type MatchingValues = [
  number | null,
  number | null,
  number | null,
  number | null,
  number | null,
  number | null,
  number | null,
  number | null,
];
export type MatchingRow = [string, string, string, ...MatchingValues];
export type MatchingComparison = [string, string, string, ...MatchingValues];
export type MatchingFlow = [string, string, string, string, ...MatchingValues];
export const matchingMetrics = [
  { label: "Helt matchade anställda", unit: "personer" },
  { label: "Delvis matchade anställda", unit: "personer" },
  { label: "Inte matchade anställda", unit: "personer" },
  { label: "Anställda utan tillräckliga uppgifter", unit: "personer" },
  { label: "Totalt antal personer (justerat)", unit: "personer" },
  { label: "Förvärvsgrad (justerad)", unit: "%" },
  { label: "Matchad förvärvsgrad", unit: "%" },
  { label: "Skillnad mellan förvärvsgrad och matchad förvärvsgrad", unit: "procentenheter" },
] as const;
export function matchingNumber(value: number | null | undefined, decimals = 1) {
  return value == null
    ? "Uppgift saknas"
    : value.toLocaleString("sv-SE", { maximumFractionDigits: decimals });
}
export function matchingValue(row: MatchingRow | undefined, metric: number): number | null {
  return row ? (row[3 + metric] as number | null) : null;
}
