import assert from "node:assert/strict";
import {
  employmentValue,
  employmentSeries,
  previousEmploymentPeriod,
  type EmploymentRow,
  type EmploymentDataset,
} from "../src/lib/employment.ts";
// Synthetic examples: zeros, protection, denominator and comparison boundaries.
const row: EmploymentRow = ["2026M01", "1+2", "bostad", "A", 20, 40, "", ""];
const old: EmploymentRow = ["2025M01", "1+2", "bostad", "A", 10, 20, "", ""];
const total: EmploymentRow = ["2026M01", "1+2", "bostad", "ALL", 100, 50, "", ""];
assert.equal(employmentValue(row, "count"), 20);
assert.equal(employmentValue(row, "rate"), 40);
assert.equal(employmentValue(row, "share", undefined, total), 20);
assert.equal(employmentValue(row, "change", old), 10);
assert.equal(employmentValue(row, "percent", old), 100);
assert.equal(employmentValue({ ...row, 4: 0 } as EmploymentRow, "count"), 0);
assert.equal(employmentValue(row, "percent", { ...old, 4: 0 } as EmploymentRow), null);
assert.equal(employmentValue({ ...row, 6: "c" } as EmploymentRow, "count"), null);
assert.equal(employmentValue(row, "change"), null);
assert.equal(employmentValue(row, "share", undefined, { ...total, 6: "c" } as EmploymentRow), null);
assert.equal(previousEmploymentPeriod("2020M01"), "2019M01");
const info = { periods: ["2025M01", "2025M02", "2026M01"], total: "ALL" } as EmploymentDataset;
const points = employmentSeries([row, old, total], info, "1+2", "bostad", "A", "change");
assert.equal(points[0]!.value, null);
assert.equal(points[1]!.value, null);
assert.equal(points[2]!.value, 10);
assert.ok(
  employmentSeries([row, old, total], info, "1+2", "arbetsstalle", "A", "count").every(
    (p) => p.value === null,
  ),
);
console.log(
  "Employment: source rate vs share, zeros, missing/protected values, perspective and calendar changes passed.",
);

const annual = {
  ...info,
  table: "TAB3204",
  periods: ["2021", "2022", "2023", "2024"],
} as EmploymentDataset;
const annualRows: EmploymentRow[] = annual.periods.map((p) => [
  p,
  "1+2",
  "bostad",
  "A",
  Number(p),
  null,
  "",
  "",
]);
const changes = employmentSeries(annualRows, annual, "1+2", "bostad", "A", "change");
assert.equal(changes[1]!.value, null);
assert.equal(changes[2]!.value, 1);
assert.equal(changes[3]!.value, null);
