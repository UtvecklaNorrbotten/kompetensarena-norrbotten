import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import catalog from "@/data/demand/catalog.json";
import {
  demandSeries,
  demandChange,
  decodeDemandLor,
  type DemandJsonStat,
  type DemandModel,
  type DemandRank,
  type DemandSelection,
} from "./labour-demand";
import { monthOffset } from "./af-unemployment";

const geo = z.string().refine((v) => v in catalog.geographies);
const selection = z
  .object({
    field: z.string().refine((v) => !v || catalog.fields.includes(v)),
    group: z.string().refine((v) => !v || v in catalog.groups),
    metric: z.enum(["new", "remaining"]),
    duration: z.enum(["all", "10", "source"]),
  })
  .refine((s) =>
    s.group ? s.metric === "remaining" && s.duration === "source" : s.duration !== "source",
  );
const period = z.string().refine((v) => catalog.dimensions.totals.periods.includes(v));

function sourcePeriods(s: DemandSelection) {
  return s.group
    ? catalog.dimensions.groups.periods
    : s.field
      ? catalog.dimensions.fields.periods
      : catalog.dimensions.totals.periods;
}

async function load(geo: string): Promise<DemandModel> {
  const { getRequest } = await import("@tanstack/react-start/server");
  const request = getRequest() as Request & {
    runtime?: {
      cloudflare?: { env?: { ASSETS?: { fetch: (request: Request) => Promise<Response> } } };
    };
  };
  const url = new URL(`/data/demand/geo-${geo}.json`, request.url);
  const assets = request.runtime?.cloudflare?.env?.ASSETS;
  const response = assets ? await assets.fetch(new Request(url)) : await fetch(url);
  if (!response.ok) throw new Error("Uppgifter kunde inte läsas för vald geografi.");
  const snapshot = (await response.json()) as { gzip: string };
  const { gunzipSync } = await import("node:zlib");
  return JSON.parse(gunzipSync(Buffer.from(snapshot.gzip, "base64")).toString());
}
export const getDemandSlice = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) => z.object({ geo, selection, period }).parse(input))
  .handler(async ({ data }) => {
    const model = await load(data.geo);
    const rows = demandSeries(model, data.selection, sourcePeriods(data.selection));
    const rank = (code: string, label: string, s: DemandSelection): DemandRank => {
      const values = new Map(
        demandSeries(model, s, sourcePeriods(s)).map((r) => [r.period, r.value]),
      );
      const value = values.get(data.period) ?? null;
      const previous = values.get(monthOffset(data.period, -12)) ?? null;
      return { code, label, value, previous, change: demandChange(value, previous) };
    };
    return {
      rows,
      fields: catalog.fields.map((f) =>
        rank(f, f, {
          ...data.selection,
          field: f,
          group: "",
          duration: data.selection.duration === "source" ? "all" : data.selection.duration,
        }),
      ),
      groups: Object.entries(catalog.groups).map(([code, label]) =>
        rank(code, `${code} ${label}`, {
          ...data.selection,
          group: code,
          metric: "remaining",
          duration: "source",
        }),
      ),
    };
  });

export const getDemandComparison = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) =>
    z
      .object({
        selection,
        period,
        county: z.string().regex(/^\d{2}$/),
        level: z.enum(["kommun", "län"]),
      })
      .parse(input),
  )
  .handler(async ({ data }): Promise<DemandRank[]> => {
    const result: DemandRank[] = [];
    for (const [code, g] of Object.entries(catalog.geographies)) {
      if (g.level !== data.level || (data.level === "kommun" && g.parent !== data.county)) continue;
      const rows = demandSeries(await load(code), data.selection, sourcePeriods(data.selection));
      const value = rows.find((r) => r.period === data.period)?.value ?? null;
      const previous = rows.find((r) => r.period === monthOffset(data.period, -12))?.value ?? null;
      result.push({ code, label: g.name, value, previous, change: demandChange(value, previous) });
    }
    return result;
  });

export const getDemandLor = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) => z.object({ geo: z.string().regex(/^\d{2}$/) }).parse(input))
  .handler(async ({ data }) => {
    const snapshots = await import("@/data/demand/lor.json");
    return Object.entries(snapshots.default).map(([table, snapshot]) => {
      const source = snapshot.data as DemandJsonStat;
      const records = decodeDemandLor(source, data.geo);
      return {
        table,
        updated: snapshot.updated,
        labels: Object.fromEntries(
          Object.entries(source.dimension).map(([id, d]) => [id, d.category.label]),
        ),
        records,
      };
    });
  });
