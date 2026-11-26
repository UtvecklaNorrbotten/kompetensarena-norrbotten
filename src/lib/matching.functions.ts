import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import catalog from "@/data/matching/catalog.json";
import type { MatchingRow, MatchingFlow, MatchingComparison } from "./matching";

const selection = z.object({
  geo: z.string().refine((v) => v in catalog.summary),
  sex: z.enum(["totalt", "1", "2"]),
  education: z.string().refine((v) => v in catalog.education),
  period: z.string().refine((v) => catalog.periods.includes(v)),
});
async function load<T>(file: string): Promise<T[]> {
  const { getRequest } = await import("@tanstack/react-start/server");
  const request = getRequest() as Request & {
    runtime?: { cloudflare?: { env?: { ASSETS?: { fetch: (r: Request) => Promise<Response> } } } };
  };
  const url = new URL(`/data/matching/${file}`, request.url);
  const assets = request.runtime?.cloudflare?.env?.ASSETS;
  const response = assets ? await assets.fetch(new Request(url)) : await fetch(url);
  if (!response.ok) throw new Error("Matchningsstatistiken kunde inte läsas. Försök igen.");
  const snapshot = (await response.json()) as { gzip: string };
  const { gunzipSync } = await import("node:zlib");
  return JSON.parse(gunzipSync(Buffer.from(snapshot.gzip, "base64")).toString());
}
export const getMatchingSlice = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) => selection.parse(input))
  .handler(async ({ data }) => {
    const files: Record<string, string> = catalog.summary;
    const flowFiles: Record<string, string> = catalog.flows;
    const [rows, national, flows] = await Promise.all([
      load<MatchingRow>(files[data.geo]!),
      data.geo === "00" ? Promise.resolve([]) : load<MatchingRow>(files["00"]!),
      flowFiles[data.geo] ? load<MatchingFlow>(flowFiles[data.geo]!) : Promise.resolve([]),
    ]);
    return {
      history: rows.filter((r) => r[0] === data.education && r[1] === data.sex),
      national: national.filter((r) => r[0] === data.education && r[1] === data.sex),
      ranking: rows.filter((r) => r[1] === data.sex && r[2] === data.period),
      flows: flows.filter(
        (r) => r[0] === data.education && r[1] === data.sex && r[2] === data.period,
      ),
      hasFlows: data.geo in flowFiles,
    };
  });
export const getMatchingComparison = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) => selection.omit({ geo: true }).parse(input))
  .handler(async ({ data }) => {
    const files: Record<string, string> = catalog.comparisons;
    return (await load<MatchingComparison>(files[data.period]!)).filter(
      (r) => r[1] === data.education && r[2] === data.sex,
    );
  });
