import assert from "node:assert/strict";
import { legendClickState } from "../src/lib/legend-click";

// Exempel: syntetiska serier och klockslag, utan väntetider eller operativsystemets gräns.
const keys = ["Kvinnor", "Män", "Total"];
let result = legendClickState(keys, [], "Män", 0, null);
result = legendClickState(keys, result.hidden, "Män", 180, result.pending);
assert.deepEqual(result.hidden, ["Kvinnor", "Total"]);
result = legendClickState(keys, result.hidden, "Män", 600, result.pending);
result = legendClickState(keys, result.hidden, "Män", 780, result.pending);
assert.deepEqual(result.hidden, []);

let slow = legendClickState(keys, [], "Män", 0, null);
slow = legendClickState(keys, slow.hidden, "Män", 221, slow.pending);
assert.deepEqual(slow.hidden, []);
assert.notEqual(slow.pending, null);

let different = legendClickState(keys, [], "Män", 0, null);
different = legendClickState(keys, different.hidden, "Kvinnor", 100, different.pending);
assert.deepEqual(different.hidden, ["Män", "Kvinnor"]);

let keyboard = legendClickState(keys, [], "Män", 0, null, true);
keyboard = legendClickState(keys, keyboard.hidden, "Män", 100, keyboard.pending, true);
assert.deepEqual(keyboard.hidden, []);
assert.equal(keyboard.pending, null);
console.log(
  "Legend: snabba dubbelklick isolerar/återställer; långsamma och tangentbordsklick förblir enkelklick.",
);
