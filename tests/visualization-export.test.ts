import assert from "node:assert/strict";
import test from "node:test";
import {
  citation,
  exportFilename,
  metadataRows,
  observation,
  periodRange,
  type VisualizationExport,
} from "../src/lib/visualization-export";

// Exempel: syntetisk export med noll, bortfall och en sekretessmarkerad uppgift.
const example: VisualizationExport = {
  title: "Exempel på utbildningsflöde",
  filename: "exempel-2025",
  period: "2024–2025",
  anchor: "exempel",
  source: {
    producer: "Exempelproducent",
    product: "Exempelprodukt",
    identifier: "TAB-EX",
    url: "https://example.org/tabell",
    retrieved: "2025-11-01T12:00:00Z",
  },
  filters: { Kön: "Kvinnor", Område: "Exempelkommun" },
  columns: ["Mått", "Värde", "Status"],
  rows: [
    ["In", ...observation(0)],
    ["Ut", ...observation(null)],
    ["Netto", ...observation(4, true)],
  ],
};

test("exporten skiljer mellan noll, saknad och skyddad uppgift", () => {
  assert.deepEqual(example.rows, [
    ["In", 0, "Publicerat"],
    ["Ut", null, "Uppgift saknas"],
    ["Netto", null, "Sekretess"],
  ]);
  assert.deepEqual(observation(NaN), [null, "Uppgift saknas"]);
});

test("metadata behåller aktuellt urval och uttagsdatum", () => {
  const metadata = Object.fromEntries(metadataRows(example));
  assert.equal(metadata["Filter – Kön"], "Kvinnor");
  assert.equal(metadata["Referensperiod"], "2024–2025");
  assert.equal(metadata["Uttagsdatum"], "2025-11-01");
  assert.equal(metadata["Originalkälla"], "https://example.org/tabell");
  assert.equal(metadata["Definition"], "");
});

test("källhänvisningen skiljer producent och visualisering och använder sidans ankare", () => {
  const text = citation(example, "https://example.org/sida?geo=01#annat");
  assert.match(text, /Källa: Exempelproducent · Exempelprodukt · TAB-EX/);
  assert.match(text, /Uttagsdatum: 2025-11-01/);
  assert.match(
    text,
    /Bearbetning och visualisering: Kompetensarena Norrbotten\. https:\/\/example.org\/sida#exempel/,
  );
  assert.doesNotMatch(text, /geo=01|#annat/);
  assert.doesNotMatch(
    citation({ ...example, source: { producer: "Exempelproducent" } }, "https://example.org"),
    /Uttagsdatum|Originalkälla/,
  );
});

test("filnamn är begripliga och periodetiketter utgår från aktuella rader", () => {
  assert.equal(exportFilename("Åldersflöden", "Luleå · 2023–2024"), "aldersfloden-lulea-2023-2024");
  assert.equal(periodRange(["2024", "2024"]), "2024");
  assert.equal(periodRange(["2024", "2025"]), "2024 – 2025");
  assert.equal(periodRange([]), undefined);
});
