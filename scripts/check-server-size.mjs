import { readdir, stat } from "node:fs/promises";
import { join } from "node:path";

// Hosting's dynamic Worker cap is 64 MiB. Leave 4 MiB for packaging overhead.
const budget = 60 * 1024 * 1024;
async function codeSize(directory) {
  let bytes = 0;
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) bytes += await codeSize(path);
    else if (/\.(mjs|js|cjs|wasm)$/.test(entry.name)) bytes += (await stat(path)).size;
  }
  return bytes;
}
const bytes = await codeSize(".output/server");
console.log(
  `Server code: ${(bytes / 1024 / 1024).toFixed(1)} MiB / ${budget / 1024 / 1024} MiB budget`,
);
if (bytes > budget) {
  throw new Error(
    "Server code exceeds hosting budget. Move statistical snapshots to public assets before publishing.",
  );
}
