import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import snapshot from "@/data/employment/catalog.json";
import { employmentSeries, type EmploymentCatalog, type EmploymentRow } from "./employment";
const catalog = snapshot as EmploymentCatalog;
const dataset = z.string().refine((v) => v in catalog.datasets);
const geo = z.string().refine((v) => v in catalog.geographies);
async function load(name: string): Promise<EmploymentRow[]> {
  const file = catalog.files[name];
  if (!file) throw new Error("Det finns inga uppgifter för urvalet.");
  const { getRequest } = await import("@tanstack/react-start/server");
  const request = getRequest() as Request & {
    runtime?: { cloudflare?: { env?: { ASSETS?: { fetch: (r: Request) => Promise<Response> } } } };
  };
  const url = new URL(`/data/employment/${file.path}`, request.url);
  const assets = request.runtime?.cloudflare?.env?.ASSETS;
  const response = assets ? await assets.fetch(new Request(url)) : await fetch(url);
  if (!response.ok) throw new Error("Sysselsättningsuppgifterna kunde inte läsas. Försök igen.");
  const { gzip } = (await response.json()) as { gzip: string };
  const { gunzipSync } = await import("node:zlib");
  return JSON.parse(gunzipSync(Buffer.from(gzip, "base64")).toString());
}
export const getEmploymentSlice = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) =>
    z
      .object({
        dataset,
        geo,
        sex: z.enum(["1", "2", "1+2"]),
        perspective: z.enum(["arbetsstalle", "bostad"]),
      })
      .parse(input),
  )
  .handler(async ({ data }) =>
    (await load(`${data.dataset}/geo-${data.geo}.json`)).filter(
      (r) => r[1] === data.sex && r[2] === data.perspective,
    ),
  );
export const getEmploymentComparison = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) =>
    z
      .object({
        dataset,
        period: z.string().regex(/^\d{4}(M\d{2})?$/),
        sex: z.enum(["1", "2", "1+2"]),
        perspective: z.enum(["arbetsstalle", "bostad"]),
        category: z.string().max(40),
        county: z.string().regex(/^\d{2}$/),
        level: z.enum(["kommun", "lan"]),
        metric: z.enum(["count", "share", "rate", "change", "percent"]),
      })
      .parse(input),
  )
  .handler(async ({ data }) => {
    const info = catalog.datasets[data.dataset]!;
    if (!info.periods.includes(data.period) || !(data.category in info.categories))
      throw new Error("Ogiltigt period- eller kategoriurval.");
    const previous = `${Number(data.period.slice(0, 4)) - 1}${data.period.slice(4)}`;
    const current = await load(`${data.dataset}/period-${data.period}.json`);
    const old = info.periods.includes(previous)
      ? await load(`${data.dataset}/period-${previous}.json`)
      : [];
    const grouped = new Map<string, EmploymentRow[]>();
    for (const [period, records] of [
      [data.period, current],
      [previous, old],
    ] as const) {
      for (const r of records) {
        if (
          r[1] !== data.sex ||
          r[2] !== data.perspective ||
          (r[3] !== data.category && r[3] !== info.total)
        )
          continue;
        const list = grouped.get(r[0]) ?? [];
        list.push([period, ...r.slice(1)] as EmploymentRow);
        grouped.set(r[0], list);
      }
    }
    // Period files replace column zero with geography. Filter before returning.
    return Object.entries(catalog.geographies)
      .filter(([g]) =>
        data.level === "lan"
          ? g.length === 2 && g !== "00"
          : g.length === 4 && g.startsWith(data.county),
      )
      .map(([geo, label]) => {
        const rows = grouped.get(geo) ?? [];
        const point = employmentSeries(
          rows,
          info,
          data.sex,
          data.perspective,
          data.category,
          data.metric,
        ).find((r) => r.period === data.period);
        return { code: geo, label, value: point?.value ?? null, status: point?.status ?? "" };
      });
  });
