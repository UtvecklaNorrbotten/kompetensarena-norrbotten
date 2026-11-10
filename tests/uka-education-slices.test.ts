import assert from "node:assert/strict";
import {
  selectUkaRows,
  ukaCatalogEntry,
  ukaTarget,
  dimensions,
  type UkaFilters,
  type UkaRow,
} from "../src/lib/uka-view";
import { readAllUkaPages, toUkaRows, catalogComboRows } from "../src/lib/uka-education";
import { dimensionOptions } from "../src/lib/uka-view";

// Exempel: syntetiska rader som efterliknar HST (ålder, ämnen, studieform) över två perioder.
const row = (changes: Partial<UkaRow>): UkaRow => ({
  indicator_id: "uka-hst",
  university: "Riket",
  period: "2024",
  gender: "Total",
  breakdown: "",
  category: "",
  value: 1,
  ...changes,
});
const rows: UkaRow[] = [];
let v = 1;
for (const period of ["2023", "2024", "2025"])
  for (const gender of ["Kvinnor", "Män", "Total"]) {
    rows.push(row({ period, gender, value: v++ }));
    for (const omr of ["Teknik", "Vård"]) {
      rows.push(row({ period, gender, breakdown: "amnesomrade", category: omr, value: v++ }));
      for (const sf of ["Campus", "Distans"])
        rows.push(
          row({ period, gender, breakdown: "amnesomrade|studieform", category: `${omr}|${sf}`, value: v++ }),
        );
      for (const age of ["-24", "25-"]) {
        rows.push(row({ period, gender, breakdown: "aldersgrupp", category: age, value: v++ }));
        rows.push(
          row({ period, gender, breakdown: "aldersgrupp|amnesomrade", category: `${age}|${omr}`, value: v++ }),
        );
      }
    }
  }
// Vårdens 0 är ett källvärde, en saknad cell är null; inget av dem får ändras.
rows.push(row({ period: "2025", gender: "Kvinnor", breakdown: "studieform", category: "Campus", value: 0 }));
rows.push(row({ period: "2025", gender: "Män", breakdown: "studieform", category: "Campus", value: null }));

const entry = ukaCatalogEntry(rows);
/** Servern: exakt uppdelning och positionsvis kategorimatchning, som uka_education_slice. */
function serverSlice(target: ReturnType<typeof ukaTarget>): UkaRow[] {
  if (target.breakdown === undefined) return [];
  return rows.filter(
    (r) =>
      r.breakdown === target.breakdown &&
      Object.entries(target.selection).every(([k, val]) => dimensions(r)[k] === val),
  );
}
const cases: UkaFilters[] = [
  { gender: "Total", years: 5, dimensions: {} },
  { gender: "Kvinnor", years: 1, dimensions: {} },
  { gender: "Total", years: 5, dimensions: { amnesomrade: "Teknik" } },
  { gender: "Total", years: 2, dimensions: { studieform: "Distans" } },
  { gender: "Total", years: 5, dimensions: { studieform: "Campus", amnesomrade: "Vård" } },
  { gender: "Total", years: 5, dimensions: { aldersgrupp: "-24" } },
  { gender: "Total", years: 5, dimensions: { aldersgrupp: "25-", amnesomrade: "Vård" } },
  { gender: "Total", years: 5, dimensions: { program: "Finns inte här" } },
  { gender: "Total", years: 5, dimensions: { amnesomrade: "Finns inte" } },
];
for (const filters of cases)
  for (const detail of [false, true]) {
    const full = selectUkaRows(rows, filters, detail);
    const slice = selectUkaRows(serverSlice(ukaTarget(entry, filters, detail)), filters, detail, entry);
    assert.deepEqual(slice, full, JSON.stringify({ filters, detail }));
  }
// Urvalet är litet trots att hela indikatorn är stor: översikten hämtar bara totalraderna.
assert.equal(serverSlice(ukaTarget(entry, cases[0]!)).length, 9);
assert.equal(ukaTarget(entry, cases[0]!, true).breakdown, "amnesomrade");
// Saknade värden förblir null och källans nollor förblir 0.
const sf = selectUkaRows(serverSlice(ukaTarget(entry, cases[3]!, true)), cases[3]!, true, entry);
assert.equal(sf.breakdown, "studieform");
const campusOnly = selectUkaRows(
  serverSlice(ukaTarget(entry, { ...cases[0]!, dimensions: { studieform: "Campus" } }, true)),
  { ...cases[0]!, dimensions: { studieform: "Campus" } },
  true,
  entry,
);
assert.equal(campusOnly.rows.find((r) => r.gender === "Kvinnor")?.value, 0);
assert.equal(campusOnly.rows.find((r) => r.gender === "Män")?.value, null);
assert.equal(campusOnly.rows.length, 2);
const campus = selectUkaRows(
  serverSlice(ukaTarget(entry, { ...cases[0]!, dimensions: {} }, true)),
  cases[0]!,
  true,
  entry,
);
assert.ok(campus.rows.every((r) => r.breakdown === "amnesomrade"));
// Filteralternativ från katalogens kombinationer = från alla rader.
const combos: Record<string, string[]> = {};
for (const r of rows) if (!(combos[r.breakdown] ??= []).includes(r.category)) combos[r.breakdown]!.push(r.category);
for (const filters of cases)
  assert.deepEqual(
    dimensionOptions(catalogComboRows(combos), filters.dimensions),
    dimensionOptions(rows, filters.dimensions),
  );
console.log("UKÄ-urval: delmängd per uppdelning ger samma figurdata som hela indikatorn.");

// Exempel: sidläsning är komplett och varje svar begränsat; inget tyst avbrott.
const pages = Array.from({ length: 10 }, (_, i) => ({ period: `p${i}`, gender: "Total", category: "", value: i }));
const seen: number[] = [];
const all = await readAllUkaPages(async (offset) => {
  seen.push(offset);
  const rowsOut = pages.slice(offset, offset + 4);
  return { rows: rowsOut, next: offset + 4 < pages.length ? offset + 4 : null };
});
assert.deepEqual(seen, [0, 4, 8]);
assert.equal(all.length, 10);
await assert.rejects(
  readAllUkaPages(async () => ({ rows: [], next: 0 })),
  /fullständigt/,
);
await assert.rejects(
  readAllUkaPages(async (offset) => ({ rows: [], next: offset + 1 }), 3),
  /fullständigt/,
);
assert.equal(toUkaRows("uka-hst", "Riket", "x", [pages[1]!])[0]?.value, 1);
console.log("UKÄ-sidläsning: komplett, begränsad och felar tydligt.");
