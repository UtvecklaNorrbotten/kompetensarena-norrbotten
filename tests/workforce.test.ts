import assert from "node:assert/strict";
import {
  workforceValue,
  workforcePoint,
  workforceChange,
  workforceSegment,
  type WorkforceRow,
  type WorkforceDataset,
} from "../src/lib/workforce.ts";
const rows: WorkforceRow[] = [
  ["2023M08", "1+2", "20-64", "20-64", "count", 100, ""],
  ["2024M08", "1+2", "20-64", "20-64", "count", 115, ""],
  ["2024M08", "2", "20-64", "20-64", "count", 50, ""],
  ["2024M08", "1+2", "15-74", "15-74", "count", 200, ""],
  ["2024M08", "1+2", "20-64", "20-64", "rate", 75.4, ""],
];
assert.equal(
  workforceValue(workforcePoint(rows, "2024M08", "1+2", "20-64", "20-64", "count")),
  115,
);
assert.equal(workforceValue(workforcePoint(rows, "2024M08", "1", "20-64", "20-64", "count")), null);
assert.equal(workforceValue(["2024", "1", "x", "", "n", 0, ""]), 0);
assert.equal(workforceValue(["2024", "1", "x", "", "n", 5, ".."]), null);
assert.equal(
  workforceChange(rows, "2024M08", "1+2", "20-64", "20-64", "count", {
    table: "TAB6260",
  } as WorkforceDataset),
  15,
);
for (const [table, period] of [
  ["TAB6371", "2022"],
  ["TAB6368", "2022"],
  ["TAB4435", "2023"],
  ["TAB4435", "2024"],
  ["TAB5543", "2024"],
]) {
  assert.equal(
    workforceChange(rows, period, "1+2", "20-64", "20-64", "count", { table } as WorkforceDataset),
    null,
  );
  assert.notEqual(
    workforceSegment(table, period),
    workforceSegment(table, String(Number(period) - 1)),
  );
}
console.log("Workforce selection, missing values and method boundaries verified.");
