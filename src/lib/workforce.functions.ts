import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import snapshot from "@/data/workforce/catalog.json";
import type { WorkforceCatalog, WorkforceRow } from "./workforce";
const catalog = snapshot as WorkforceCatalog;
const dataset = z.string().refine((v) => v in catalog.datasets);
async function load(name: string): Promise<WorkforceRow[]> {
  const file = catalog.files[name];
  if (!file) throw new Error("Uppgifter saknas för denna geografi och detta underlag.");
  const { getRequest } = await import("@tanstack/react-start/server");
  const request = getRequest() as Request & {
    runtime?: { cloudflare?: { env?: { ASSETS?: { fetch: (r: Request) => Promise<Response> } } } };
  };
  const url = new URL(`/data/workforce/${file.path}`, request.url);
  const assets = request.runtime?.cloudflare?.env?.ASSETS;
  const response = assets ? await assets.fetch(new Request(url)) : await fetch(url);
  if (!response.ok) throw new Error("Arbetskraftsstatistiken kunde inte läsas. Försök igen.");
  const { gzip } = (await response.json()) as { gzip: string };
  const { gunzipSync } = await import("node:zlib");
  return JSON.parse(gunzipSync(Buffer.from(gzip, "base64")).toString());
}
export const getWorkforceSlice = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) =>
    z.object({ dataset, geo: z.string().refine((v) => v in catalog.geographies) }).parse(input),
  )
  .handler(async ({ data }) => load(`${data.dataset}/geo-${data.geo}.json`));
export const getWorkforceComparison = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) =>
    z
      .object({
        dataset,
        period: z.string(),
        sex: z.string(),
        category: z.string(),
        age: z.string(),
        measure: z.string(),
      })
      .parse(input),
  )
  .handler(async ({ data }) => {
    const info = catalog.datasets[data.dataset]!;
    if (
      !info.periods.includes(data.period) ||
      !info.sexes.includes(data.sex) ||
      !(data.category in info.categories) ||
      !(data.measure in info.measures) ||
      (Object.keys(info.ages).length && !(data.age in info.ages))
    )
      throw new Error("Ogiltigt urval.");
    return (await load(`${data.dataset}/period-${data.period}.json`))
      .filter(
        (r) =>
          r[1] === data.sex && r[2] === data.category && r[3] === data.age && r[4] === data.measure,
      )
      .map((r) => ({
        code: r[0],
        label: catalog.geographies[r[0]]!,
        value: r[6] ? null : r[5],
        status: r[6],
      }));
  });
