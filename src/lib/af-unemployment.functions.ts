import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import type { AfGeoData, AfPair } from "./af-unemployment";
import catalog from "@/data/af/catalog.json";

type AfComparisonRow = [string, string, string, number | null | "<5", number | null | "<5"];

// Per-geography/month files live in public/data/af and are read via ASSETS so the Worker stays small.
async function load<T>(file: string, missing: string): Promise<T> {
  const { getRequest } = await import("@tanstack/react-start/server");
  const request = getRequest() as Request & {
    runtime?: { cloudflare?: { env?: { ASSETS?: { fetch: (r: Request) => Promise<Response> } } } };
  };
  const url = new URL(`/data/af/${file}`, request.url);
  const assets = request.runtime?.cloudflare?.env?.ASSETS;
  const response = assets ? await assets.fetch(new Request(url)) : await fetch(url);
  if (response.status === 404) throw new Error(missing);
  if (!response.ok) throw new Error("Arbetslöshetsstatistiken kunde inte läsas. Försök igen.");
  const { gzip } = (await response.json()) as { gzip: string };
  const { gunzipSync } = await import("node:zlib");
  return JSON.parse(gunzipSync(Buffer.from(gzip, "base64")).toString()) as T;
}

const geo = z.string().refine((value) => value in catalog.geographies, "Okänd geografi");
const period = z.enum(catalog.periods as [string, ...string[]]);

export const getAfUnemployment = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) => z.object({ geo, sex: z.enum(["", "K", "M"]) }).parse(input))
  .handler(async ({ data }): Promise<AfGeoData> => {
    const snapshot = await load<AfGeoData>(`geo-${data.geo}.json`, "Statistik saknas för vald geografi.");
    return {
      pairs: snapshot.pairs.filter((r) => r[2] === data.sex),
      history: snapshot.history.filter((r) => r[1] === data.sex),
    };
  });

export const getAfUnemploymentComparison = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) =>
    z
      .object({
        period,
        group: z.enum(["total", "young", "older", "domestic", "foreign", "pre", "upper", "post"]),
        sex: z.enum(["", "K", "M"]),
      })
      .parse(input),
  )
  .handler(async ({ data }): Promise<{ geo: string; row: AfPair }[]> => {
    const rows = await load<AfComparisonRow[]>(
      `compare-${data.period}.json`,
      "Statistik saknas för vald månad.",
    );
    return rows
      .filter((r) => r[1] === data.group && r[2] === data.sex)
      .map(([code, group, sex, count, workforce]) => ({
        geo: code,
        row: [data.period, group, sex, count, workforce],
      }));
  });

export const getAfUnemploymentGroups = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) => z.object({ geo, period }).parse(input))
  .handler(async ({ data }): Promise<AfPair[]> => {
    const snapshot = await load<AfGeoData>(`geo-${data.geo}.json`, "Statistik saknas för vald geografi.");
    return snapshot.pairs.filter((r) => r[0] === data.period);
  });
