import assert from "node:assert/strict";
import { educationCsv, exportFilename, wrapChartLabel } from "../src/lib/education-export";
import type { UkaRow } from "../src/lib/uka-view";

// Exempel: syntetiska etiketter och värden för att verifiera CSV-exporten.
const rows: UkaRow[] = [
  {
    indicator_id: "uka-hst",
    university: "Exempeluniversitet",
    period: "2024/25",
    gender: "Kvinnor",
    breakdown: "amnesomrade",
    category: 'Teknik; "bygg"',
    value: 12.5,
  },
  {
    indicator_id: "uka-hst",
    university: "Exempeluniversitet",
    period: "2024/25",
    gender: "Män",
    breakdown: "amnesomrade",
    category: "=Exempel",
    value: null,
  },
];
const csv = educationCsv(rows, "Helårsstudenter", "HST");
assert.ok(csv.startsWith("\uFEFF"));
assert.equal(csv.split("\r\n").length, 3);
assert.ok(csv.includes('"12,5"'));
assert.ok(csv.includes('"Teknik; ""bygg"""'));
assert.ok(csv.includes('"\'=Exempel"'));
assert.ok(csv.includes('"Män";"";"HST"'));
assert.equal(
  exportFilename("uka-hst", "Luleå tekniska universitet"),
  "uka-hst-lulea-tekniska-universitet",
);
const label = "Specialistsjuksköterskeexamen med inriktning mot intensivvård";
const lines = wrapChartLabel(label, 26);
assert.ok(lines.every((line) => line.length <= 26));
assert.equal(lines.join("").replaceAll(" ", ""), label.replaceAll(" ", ""));
assert.ok(!lines.some((line) => line.includes("…")));
console.log(
  "CSV: rader, saknade värden, decimaler, svenska tecken och fullständiga etiketter godkända.",
);
