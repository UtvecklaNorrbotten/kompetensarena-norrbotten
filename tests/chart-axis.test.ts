import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { countAxis, educationAxis } from "../src/lib/education-axis.ts";

// Syntetiska gränsfall: noll, små värden, negativa netton och blandade tecken.
for (const values of [
  [],
  [0],
  [1, 2, 3],
  [-41, -22, -1],
  [-12, 0, 13],
  [151, 153, 159],
  [NaN, Infinity, 12],
  [1.1, 1.7],
]) {
  const axis = countAxis(values);
  assert(axis.ticks.includes(0), "Noll måste alltid visas");
  assert(axis.ticks.every(Number.isInteger), "Axelsteg måste vara heltal");
  for (let i = 1; i < axis.ticks.length; i++)
    assert.equal(axis.ticks[i]! - axis.ticks[i - 1]!, axis.step);
  const finite = values.filter(Number.isFinite);
  for (const value of finite) assert(value >= axis.minimum && value <= axis.maximum);
  const high = Math.max(0, ...finite);
  if (high > 0) assert(axis.maximum - high >= axis.step, "Minst ett helt stegs luft ovanför max");
  assert(axis.ticks.length <= 10, "Markeringarna ska rymmas utan att bli täta");
}
assert.deepEqual(educationAxis([15, 99], "%").ticks, [0, 20, 40, 60, 80, 100]);
assert.deepEqual(educationAxis([1.2, 2.1], "sökande per antagen").ticks, [0, 1, 2, 3, 4]);

// Verifiera samtliga befintliga U3-serier: små grupper, bortfall och teckenbyte.
const rows = JSON.parse(
  readFileSync(new URL("../src/data/rmi/25.json", import.meta.url), "utf8"),
) as (string | number | null)[][];
const series = new Map<string, number[]>();
for (const row of rows)
  for (const column of [4, 5]) {
    const key = `${row[0]}:${row[1]}:${column}`;
    const values = series.get(key) ?? [];
    if (typeof row[column] === "number") values.push(row[column] as number);
    series.set(key, values);
  }
for (const values of series.values()) {
  const axis = countAxis(values);
  assert(axis.ticks.includes(0));
  assert(values.every((v) => v >= axis.minimum && v <= axis.maximum));
  assert(axis.ticks.length <= 10);
}
console.log(`${series.size} SCB-serier och syntetiska gränsfall godkända.`);
