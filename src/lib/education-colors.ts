/** Samma kön har samma färg i översikt, fördjupning och historik. */
export function educationGenderColor(gender: string): string {
  if (gender === "Kvinnor") return "var(--chart-1)";
  if (gender === "Män") return "var(--chart-3)";
  return "var(--chart-total)";
}
