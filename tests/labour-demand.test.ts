import assert from "node:assert/strict";
import {
  demandSeries,
  rollingDemand,
  sumDemand,
  demandChange,
  decodeDemandLor,
  type DemandModel,
} from "../src/lib/labour-demand.ts";
import { readFileSync } from "node:fs";
// Synthetic fixtures: verify flow/stock handling, sparse months, suppression and classifications.
const model: DemandModel = {
  totals: [
    ["2025-01", "Ja", 10, 20, 8, 15],
    ["2025-01", "Nej", 5, 10, 4, 8],
  ],
  fields: [["2025-01", "A", "gymnasial", "Ja", 2, 3, 1, 2]],
  groups: [
    ["2025-01", "A", "1234", "Ja", 2],
    ["2025-01", "B", "1234", "Nej", 3],
  ],
};
const selection = { field: "", group: "", metric: "new" as const, duration: "all" as const };
assert.deepEqual(demandSeries(model, selection), [{ period: "2025-01", value: 15 }]);
assert.equal(
  demandSeries(model, { ...selection, metric: "remaining", duration: "10" })[0]!.value,
  23,
);
assert.equal(demandSeries(model, { ...selection, field: "A" })[0]!.value, 2);
assert.equal(
  demandSeries(model, { field: "", group: "1234", metric: "remaining", duration: "source" })[0]!
    .value,
  5,
);
assert.equal(
  demandSeries(model, { field: "A", group: "1234", metric: "remaining", duration: "source" })[0]!
    .value,
  2,
);
assert.equal(demandSeries(model, { ...selection, group: "1234" }).length, 0);
assert.equal(demandSeries(model, { ...selection, field: "Missing" })[0]!.value, null);
assert.deepEqual(demandSeries(model, selection, ["2025-01", "2025-02"]), [
  { period: "2025-01", value: 15 },
  { period: "2025-02", value: null },
]);
assert.equal(sumDemand([0, 0]), 0);
assert.equal(sumDemand([0, null]), null);
assert.equal(sumDemand([1, "<5"]), "<5");
assert.equal(sumDemand([]), null);
const months = Array.from({ length: 12 }, (_, i) => ({
  period: `2025-${String(i + 1).padStart(2, "0")}`,
  value: 10,
}));
assert.equal(rollingDemand(months, "new").at(-1)!.value, 120);
assert.equal(rollingDemand(months, "remaining").at(-1)!.value, 10);
assert.equal(rollingDemand(months, "new")[0]!.value, null);
assert.equal(
  rollingDemand(
    months.filter((r) => r.period !== "2025-05"),
    "new",
  ).at(-1)!.value,
  null,
);
assert.equal(demandChange(10, 0), 10);
assert.equal(demandChange("<5", 1), null);
// JSON object enumeration must not move county 25 ahead of county 00/01.
assert.equal(
  decodeDemandLor(
    {
      id: ["Region"],
      size: [4],
      value: [100, 200, 300, 400],
      dimension: {
        Region: { category: { index: { "00": 0, "01": 1, "25": 2, "10": 3 }, label: {} } },
      },
    },
    "25",
  )[0]!["value"],
  300,
);
const lor = JSON.parse(
  readFileSync(new URL("../src/data/demand/lor.json", import.meta.url), "utf8"),
);
const shortage = decodeDemandLor(lor.TAB6989.data, "25");
// Independent source: SCB's 2026-07-02 regional release: 1 900 ± 700 for Norrbotten, 2025.
assert.equal(
  shortage.find(
    (r) => r["Tid"] === "2025" && r["Yrke"] === "0" && r["ContentsCode"] === "000008UB",
  )!["value"],
  1900,
);
assert.equal(
  shortage.find(
    (r) => r["Tid"] === "2025" && r["Yrke"] === "0" && r["ContentsCode"] === "000008UC",
  )!["value"],
  700,
);
console.log("Labour demand calculation checks passed.");
