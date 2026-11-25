import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import type { AfGeoData, AfPair } from "./af-unemployment";
import catalog from "@/data/af/catalog.json";
const snapshots = import.meta.glob<{ default: AfGeoData }>("../data/af/geo-*.json");
const comparisons = import.meta.glob<{
  default: [string, string, string, number | null | "<5", number | null | "<5"][];
}>("../data/af/compare-*.json");
const geo = z.string().refine((value) => value in catalog.geographies, "Okänd geografi");
export const getAfUnemployment = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) => z.object({ geo, sex: z.enum(["", "K", "M"]) }).parse(input))
  .handler(async ({ data }): Promise<AfGeoData> => {
    const loader = snapshots[`../data/af/geo-${data.geo}.json`];
    if (!loader) throw new Error("Statistik saknas för vald geografi.");
    const snapshot = (await loader()).default;
    return {
      pairs: snapshot.pairs.filter((r) => r[2] === data.sex),
      history: snapshot.history.filter((r) => r[1] === data.sex),
    };
  });
export const getAfUnemploymentComparison = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) =>
    z
      .object({
        period: z.enum(catalog.periods as [string, ...string[]]),
        group: z.enum(["total", "young", "older", "domestic", "foreign", "pre", "upper", "post"]),
        sex: z.enum(["", "K", "M"]),
      })
      .parse(input),
  )
  .handler(async ({ data }): Promise<{ geo: string; row: AfPair }[]> => {
    const loader = comparisons[`../data/af/compare-${data.period}.json`];
    if (!loader) throw new Error("Statistik saknas för vald månad.");
    return (await loader()).default
      .filter((r) => r[1] === data.group && r[2] === data.sex)
      .map(([code, group, sex, count, workforce]) => ({
        geo: code,
        row: [data.period, group, sex, count, workforce],
      }));
  });

export const getAfUnemploymentGroups = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) =>
    z.object({ geo, period: z.enum(catalog.periods as [string, ...string[]]) }).parse(input),
  )
  .handler(async ({ data }): Promise<AfPair[]> => {
    const loader = snapshots[`../data/af/geo-${data.geo}.json`];
    if (!loader) throw new Error("Statistik saknas för vald geografi.");
    return (await loader()).default.pairs.filter((r) => r[0] === data.period);
  });
