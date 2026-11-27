import type { UkaRow } from "./uka-view";

export { downloadBlob, exportFilename } from "./visualization-export";

function csvCell(value: string | number | null): string {
  // Text ska förbli text när CSV öppnas i Excel, även om en etikett börjar med =.
  let text =
    value === null ? "" : typeof value === "number" ? String(value).replace(".", ",") : value;
  if (typeof value === "string" && /^[\s]*[=+@-]/.test(text)) text = `'${text}`;
  return `"${text.replaceAll('"', '""')}"`;
}

/** Exakt samma rader som den öppningsbara tabellen, inklusive saknade värden. */
export function educationCsv(rows: UkaRow[], title: string, unit: string): string {
  const header = [
    "Mått",
    "Lärosäte",
    "Period",
    "Uppdelning",
    "Grupp",
    "Kön",
    "Värde",
    "Enhet",
    "Källa",
  ];
  const data = rows.map((r) => [
    title,
    r.university,
    r.period,
    r.breakdown,
    r.category.replaceAll("|", " · ") || "Samtliga",
    r.gender === "Total" ? "Samtliga" : r.gender,
    r.value,
    unit,
    "UKÄ",
  ]);
  return "\uFEFF" + [header, ...data].map((r) => r.map(csvCell).join(";")).join("\r\n");
}

/** Radbryt hela etiketten, inklusive enstaka långa ord, utan att kasta tecken. */
export function wrapChartLabel(text: string, maxChars = 28): string[] {
  const lines: string[] = [];
  let current = "";
  for (const word of text.split(/\s+/)) {
    if (current && current.length + word.length + 1 > maxChars) {
      lines.push(current);
      current = "";
    }
    let rest = word;
    while (rest.length > maxChars) {
      if (current) {
        lines.push(current);
        current = "";
      }
      lines.push(rest.slice(0, maxChars));
      rest = rest.slice(maxChars);
    }
    current = current ? `${current} ${rest}` : rest;
  }
  if (current) lines.push(current);
  return lines.length ? lines : [""];
}
