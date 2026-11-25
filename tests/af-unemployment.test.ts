import assert from "node:assert/strict";
import {
  afRate,
  afChange,
  monthOffset,
  afSeries,
  rollingAf,
  type AfPoint,
} from "../src/lib/af-unemployment.ts";
assert.equal(afRate(0, 100), 0);
assert.equal(afRate(10, 0), null);
assert.equal(afRate("<5", 100), null);
assert.equal(afRate(10, null), null);
assert.equal(monthOffset("2026-01", -1), "2025-12");
assert.equal(monthOffset("2026-01", -12), "2025-01");
const series = afSeries(
  {
    pairs: [
      ["2025-01", "young", "", 10, 100],
      ["2025-03", "young", "", 20, 100],
    ],
    history: [],
  },
  "young",
  "",
);
assert.equal(series.length, 3);
assert.equal(series[1]!.count, null);
assert.equal(afChange(series, "2025-03", "count"), null);
const points: AfPoint[] = Array.from({ length: 13 }, (_, i) => ({
  period: monthOffset("2025-01", i),
  count: i,
  rate: 1,
  open: 0,
  program: i,
  suppressed: false,
}));
assert.equal(rollingAf(points)[10]!.count, null);
assert.equal(rollingAf(points)[11]!.count, 5.5);
assert.equal(afChange(points, "2026-01", "count"), 12);
points[6]!.count = null;
assert.equal(rollingAf(points)[11]!.count, null);
assert.equal(rollingAf(points)[11]!.rate, 1);
console.log("AF: rates, zero, suppression, calendar gaps, rolling windows and year changes passed");
