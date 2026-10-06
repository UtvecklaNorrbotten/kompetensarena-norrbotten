import assert from "node:assert/strict";
import {
  dimensionOptions,
  ukaDetailPeriods,
  formatUkaValue,
  periodOrder,
  selectUkaRows,
  ukaGenderSeries,
  ukaGenderTimeline,
  type UkaFilters,
  type UkaRow,
} from "../src/lib/uka-view";

// Exempel: syntetiska data för att kontrollera överlapp och urval.
const row = (changes: Partial<UkaRow> = {}): UkaRow => ({
  indicator_id: "uka-hst",
  university: "Exempeluniversitet",
  period: "2024/25",
  gender: "Total",
  breakdown: "",
  category: "",
  value: 100,
  ...changes,
});
const filters: UkaFilters = { gender: "Total", years: 5, dimensions: {} };
const rows = [
  row(),
  row({ gender: "Kvinnor", value: 60 }),
  row({ gender: "Män", value: 40 }),
  row({ breakdown: "amnesomrade", category: "Teknik", value: 70 }),
  row({ breakdown: "amnesomrade", category: "Vård", value: 30 }),
  row({ breakdown: "amnesgrupp|amnesomrade", category: "Maskinteknik|Teknik", value: 50 }),
];
assert.equal(selectUkaRows(rows, filters).rows.find((r) => r.gender === "Total")?.value, 100);
assert.equal(selectUkaRows(rows, filters, true).breakdown, "amnesomrade");
assert.equal(
  selectUkaRows(rows, { ...filters, dimensions: { amnesomrade: "Teknik" } }).rows[0]?.value,
  70,
);
assert.equal(
  selectUkaRows(rows, { ...filters, dimensions: { amnesgrupp: "Maskinteknik" } }).rows[0]?.value,
  50,
);
assert.equal(
  selectUkaRows(rows, { ...filters, dimensions: { amnesomrade: "Finns inte" } }).rows.length,
  0,
);
assert.equal(
  selectUkaRows(rows, { ...filters, dimensions: { program: "Exempelprogram" } }).applied.length,
  0,
);
const overlapping = [
  row({ breakdown: "examen|inriktning", category: "A|X" }),
  row({ breakdown: "examen|inriktning", category: "B|X" }),
];
assert.equal(
  selectUkaRows(overlapping, { ...filters, dimensions: { inriktning: "X" } }).ambiguous,
  true,
);
assert.equal(
  selectUkaRows(overlapping, { ...filters, dimensions: { inriktning: "X" } }).rows.length,
  0,
);
const nullRows = selectUkaRows([row({ value: null })], filters).rows;
assert.equal(nullRows[0]?.value, null);
assert.equal(
  selectUkaRows([row({ gender: "Total" })], { ...filters, gender: "Män" }).rows.filter(
    (r) => r.gender === "Män",
  ).length,
  0,
);
assert.ok(periodOrder("VT2026") > periodOrder("HT2025"));
assert.ok(periodOrder("HT2025") > periodOrder("VT2025"));
assert.equal(
  selectUkaRows([row({ period: "2024/25" }), row({ period: "2023/24" })], { ...filters, years: 1 })
    .rows.length,
  1,
);
assert.deepEqual(dimensionOptions(rows, {})["amnesomrade"], ["Teknik", "Vård"]);
console.log("UKÄ: totaler, kön, hierarkier, saknade värden och perioder godkända.");

// Exempel: fem år från vårterminen omfattar också höstterminen fem år bakåt.
const semesters = [
  "HT2021",
  "VT2022",
  "HT2022",
  "VT2023",
  "HT2023",
  "VT2024",
  "HT2024",
  "VT2025",
  "HT2025",
  "VT2026",
].map((period) => row({ period }));
assert.equal(selectUkaRows(semesters, filters).rows.length, 10);
assert.deepEqual(
  selectUkaRows(semesters, { ...filters, years: 1 }).rows.map((r) => r.period),
  ["HT2025", "VT2026"],
);

// Exempel: kön visas samtidigt utan att totalen räknas om.
const genderExample = [
  row({ gender: "Kvinnor", value: 60 }),
  row({ gender: "Män", value: 40 }),
  row({ value: 100 }),
  row({ period: "2023/24", gender: "Kvinnor", value: null }),
];
assert.deepEqual(ukaGenderSeries(genderExample), ["Kvinnor", "Män", "Total"]);
const genderTimeline = ukaGenderTimeline(genderExample, ukaGenderSeries(genderExample));
assert.equal(genderTimeline[1]?.["Kvinnor"], 60);
assert.equal(genderTimeline[1]?.["Män"], 40);
assert.equal(genderTimeline[0]?.["Kvinnor"], null);
assert.equal(genderTimeline[0]?.["Män"], null);
assert.deepEqual(ukaGenderSeries([row()]), ["Total"]);
assert.equal(ukaGenderTimeline([row()], ["Total"])[0]?.["Total"], 100);
assert.deepEqual(ukaGenderSeries([row({ gender: "Kvinnor" })]), ["Kvinnor", "Män"]);

assert.equal(genderTimeline[1]?.["Total"], 100);
assert.equal(formatUkaValue(3.3, "sökande per antagen"), "3,3");
assert.equal(formatUkaValue(3, "sökande per antagen"), "3,0");
// Exempel: totalen följer samma kronologiska HT/VT-axel som kvinnorna och männen.
const chronological = ukaGenderTimeline(
  [
    row({ period: "HT2025", value: 100 }),
    row({ period: "VT2025", value: 40 }),
    row({ period: "VT2026", value: 50 }),
  ],
  ["Total"],
);
assert.deepEqual(
  chronological.map((point) => point["period"]),
  ["VT 2025", "HT 2025", "VT 2026"],
);
assert.deepEqual(
  chronological.map((point) => point["Total"]),
  [40, 100, 50],
);

// Exempel: senaste kompletta kalenderår, separat HT/VT och inget summerat värde.
const detailPeriods = ukaDetailPeriods(semesters);
assert.equal(detailPeriods.year, "2025");
assert.deepEqual(detailPeriods.periods, ["VT2025", "HT2025"]);
assert.equal(detailPeriods.rows.length, 2);
assert.deepEqual(ukaDetailPeriods(semesters, "2026").periods, ["VT2026"]);
assert.equal(ukaDetailPeriods(semesters, "2026", "HT").rows.length, 0);
assert.deepEqual(ukaDetailPeriods(semesters, "2025", "HT").periods, ["HT2025"]);
assert.deepEqual(ukaDetailPeriods([row()], "").periods, ["2024/25"]);
