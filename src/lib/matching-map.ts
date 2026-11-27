export type MatchingMapRow = [string, string, number | null, number | null, number, number];
export type MatchingMapDirection = "education" | "occupation";
export const matchingMapCategories = ["Helt matchad", "Delvis matchad", "Inte matchad"];
export function matchingMapCategory(row: MatchingMapRow) {
  return row[4] === 2 ? 2 : row[4] === 0 && row[5] === 0 ? 0 : 1;
}
export function matchingMapAssessment(row: MatchingMapRow) {
  const subject = ["Helt rätt inriktning", "Delvis rätt inriktning", "Ingen ämnesmatchning"][
    row[4]
  ];
  const level = ["Rätt nivå", "För hög utbildningsnivå", "För låg utbildningsnivå"][row[5]];
  return `${subject} · ${level}`;
}
export function sortMatchingMap(
  rows: MatchingMapRow[],
  direction: MatchingMapDirection,
  names: Record<string, string>,
) {
  const shareIndex = direction === "education" ? 2 : 3;
  const nameIndex = direction === "education" ? 1 : 0;
  return [...rows].sort(
    (a, b) =>
      matchingMapCategory(a) - matchingMapCategory(b) ||
      (b[shareIndex] ?? -1) - (a[shareIndex] ?? -1) ||
      names[a[nameIndex]]!.localeCompare(names[b[nameIndex]]!, "sv") ||
      a[nameIndex].localeCompare(b[nameIndex], "sv"),
  );
}
