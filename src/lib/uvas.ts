export type UvasRow = [
  geo: string,
  age: string,
  sex: string,
  origin: string,
  category: string,
  count: number | null,
  countStatus: string,
  countRaw: string,
  share: number | null,
  shareStatus: string,
  shareRaw: string,
];
export function uvasValue(value: number | null | undefined, status?: string) {
  return status === "suppressed"
    ? "Sekretess"
    : typeof value === "number"
      ? value.toLocaleString("sv-SE", { maximumFractionDigits: 1 })
      : "Uppgift saknas";
}
