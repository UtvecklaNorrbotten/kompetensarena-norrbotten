import assert from "node:assert/strict";
import { matchingMapCategory, sortMatchingMap, type MatchingMapRow } from "../src/lib/matching-map";
// Syntetiska exempel: kategorier går före andel; sortering använder oavrundade värden.
const rows: MatchingMapRow[] = [
  ["e", "z", 0.8, 0.01, 2, 0],
  ["e", "a", 0.1, 0.9, 0, 0],
  ["e", "b", 0.2, 0.8, 0, 0],
  ["e", "c", 0.2, 0.7, 0, 0],
  ["e", "d", null, null, 0, 0],
  ["e", "f", 0.3, 0.5, 0, 2],
];
const names = { z: "Z", a: "A", b: "B", c: "C", d: "D", f: "F", e: "E" };
assert.deepEqual(
  sortMatchingMap(rows, "education", names).map((r) => r[1]),
  ["b", "c", "a", "d", "f", "z"],
);
assert.deepEqual(
  sortMatchingMap(rows, "occupation", names).map((r) => r[1]),
  ["a", "b", "c", "d", "f", "z"],
);
for (let subject = 0; subject < 3; subject++)
  for (let level = 0; level < 3; level++) {
    assert.equal(
      matchingMapCategory(["e", "o", 0, 0, subject, level]),
      subject === 2 ? 2 : subject === 0 && level === 0 ? 0 : 1,
    );
  }
assert.deepEqual(
  rows.map((r) => r[1]),
  ["z", "a", "b", "c", "d", "f"],
);
console.log("Matching map sorting and nine assessments passed.");
