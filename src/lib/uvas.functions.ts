import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import catalog from "@/data/uvas/catalog.json";
import type { UvasRow } from "./uvas";
// Published aggregate files stay outside the dynamic Worker's code size limit.
async function loadYear(year: string): Promise<UvasRow[]> {
  const { getRequest } = await import("@tanstack/react-start/server");
  const request = getRequest() as Request & {
    runtime?: { cloudflare?: { env?: { ASSETS?: { fetch: (r: Request) => Promise<Response> } } } };
  };
  const url = new URL(`/data/uvas/${year}.json`, request.url);
  const assets = request.runtime?.cloudflare?.env?.ASSETS;
  const response = assets ? await assets.fetch(new Request(url)) : await fetch(url);
  if (!response.ok) throw new Error("Publicerad UVAS-årgång kunde inte läsas.");
  return response.json();
}
export const getUvasView = createServerFn({ method: "GET" })
  .inputValidator((v: unknown) =>
    z
      .object({
        geo: z.string().regex(/^(00|\d{2}|\d{4})$/),
        age: z.enum(["16-24", "25-29", "16-29"]),
        sex: z.enum(["Totalt", "Kvinnor", "Män"]),
        origin: z.enum(["Totalt", "Inrikesfödd", "Utrikesfödd"]),
        year: z.string().regex(/^\d{4}$/),
      })
      .parse(v),
  )
  .handler(async ({ data }) => {
    const history: { year: string; row: UvasRow }[] = [];
    let comparison: UvasRow[] = [];
    for (const year of catalog.years as string[]) {
      const rows = (await loadYear(year)).filter(
        (r) => r[1] === data.age && r[2] === data.sex && r[3] === data.origin && r[4] === "Master",
      );
      for (const row of rows)
        if (row[0] === data.geo || row[0] === "00") history.push({ year, row });
      if (year === data.year) comparison = rows;
    }
    return { history, comparison };
  });
