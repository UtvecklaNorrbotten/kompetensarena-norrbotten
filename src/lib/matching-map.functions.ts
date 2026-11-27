import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import catalog from "@/data/matching-map/catalog.json";
import type { MatchingMapRow } from "./matching-map";

export const getMatchingMap = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) =>
    z
      .object({
        direction: z.enum(["education", "occupation"]),
        code: z.string(),
      })
      .refine(
        (s) => s.code in (s.direction === "education" ? catalog.educations : catalog.occupations),
        {
          message: "Välj en utbildning eller ett yrke i listan.",
        },
      )
      .parse(input),
  )
  .handler(async ({ data }) => {
    const { getRequest } = await import("@tanstack/react-start/server");
    const request = getRequest() as Request & {
      runtime?: {
        cloudflare?: { env?: { ASSETS?: { fetch: (r: Request) => Promise<Response> } } };
      };
    };
    const url = new URL(`/data/matching-map/${catalog.file}`, request.url);
    const assets = request.runtime?.cloudflare?.env?.ASSETS;
    const response = assets ? await assets.fetch(new Request(url)) : await fetch(url);
    if (!response.ok) throw new Error("Matchningskartan kunde inte läsas.");
    const snapshot = (await response.json()) as { gzip: string };
    const { gunzipSync } = await import("node:zlib");
    const rows = JSON.parse(
      gunzipSync(Buffer.from(snapshot.gzip, "base64")).toString(),
    ) as MatchingMapRow[];
    return rows.filter((r) => r[data.direction === "education" ? 0 : 1] === data.code);
  });
