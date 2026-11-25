import assert from "node:assert/strict";
import {
  durationBands,
  durationValue,
  durationText,
  type DurationRow,
} from "../src/lib/af-duration.ts";
// Exempel: syntetiska statistikvärden för att pröva beräkningsreglerna.
const row: DurationRow = {
  geo_code: "25",
  period: "2026-10",
  dimension_type: "totalt",
  dimension_value: "Totalt",
  total: 100,
  over6: 60,
  over12: 40,
  over24: 10,
  lower6: false,
  lower12: false,
  lower24: false,
};
assert.deepEqual(durationBands(row, "count"), [40, 20, 30, 10]);
assert.equal(
  durationBands(row, "count").reduce<number>((s, v) => s + v!, 0),
  row.total,
);
assert.equal(durationValue(row, "over12", "share"), 40);
assert.deepEqual(durationBands({ ...row, total: 200 }, "share"), [70, 10, 15, 5]);
assert.equal(durationValue({ ...row, lower12: true }, "over12", "count"), null);
assert.equal(durationValue({ ...row, lower12: true }, "over12", "share"), null);
assert.deepEqual(durationBands({ ...row, lower24: true }, "count"), [null, null, null, null]);
assert.equal(
  durationText({ ...row, lower12: true, over12: 0 }, "over12", "count"),
  "Sekretessmarkerat",
);
assert.equal(durationValue({ ...row, over12: 0 }, "over12", "count"), 0);
assert.equal(durationValue({ ...row, total: 0, over12: 0 }, "over12", "share"), null);
assert.equal(durationValue({ ...row, total: null }, "over12", "share"), null);
assert.equal(durationValue({ ...row, total: null }, "over12", "count"), 40);
assert.deepEqual(durationBands({ ...row, over12: null }, "count"), [null, null, null, null]);
assert.deepEqual(durationBands({ ...row, over12: 70 }, "count"), [null, null, null, null]);
assert.equal(durationValue({ ...row, over12: 101 }, "over12", "share"), null);
assert.equal(durationValue(undefined, "over12", "count"), null);
console.log("AF duration: intervals, denominator, suppression, missing values and zero passed.");
