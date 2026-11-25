import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { publicClient } from "./aggregates.functions";
import type { DurationRow } from "./af-duration";

const geo = z.string().regex(/^(00|\d{2}|\d{4})$/);
const fields =
  "geo_code,period,dimension_type,dimension_value,total,over6,over12,over24,lower6,lower12,lower24";
export const getAfDurationCatalog = createServerFn({ method: "GET" }).handler(async () => {
  const client = publicClient();
  const [geographies, latest, first, metadata] = await Promise.all([
    client.from("geographies").select("code,name,level,parent_code").order("code").limit(500),
    client
      .from("agg_af_duration")
      .select("period")
      .eq("geo_code", "00")
      .eq("dimension_type", "totalt")
      .order("period", { ascending: false })
      .limit(1),
    client
      .from("agg_af_duration")
      .select("period")
      .eq("geo_code", "00")
      .eq("dimension_type", "totalt")
      .order("period")
      .limit(1),
    client
      .from("indicator_metadata")
      .select("indicator_id,hamtad_datum,period")
      .in("indicator_id", ["af-tid-utan-arbete", "af-arbetssokande"]),
  ]);
  if ([geographies, latest, first, metadata].some((r) => r.error))
    throw new Error("Kunde inte läsa Arbetsförmedlingens statistik. Försök igen.");
  return {
    geographies: geographies.data ?? [],
    latest: latest.data?.[0]?.period ?? null,
    first: first.data?.[0]?.period ?? null,
    metadata: metadata.data ?? [],
  };
});
export const getAfDurationHistory = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) => z.object({ geo }).parse(input))
  .handler(async ({ data }): Promise<DurationRow[]> => {
    const client = publicClient();
    const rows: DurationRow[] = [];
    // Totalserien: begränsade sidor, så PostgRESTs radtak inte kapar historiken.
    for (let offset = 0; offset < 10000; offset += 1000) {
      const page = await client
        .from("agg_af_duration")
        .select(fields)
        .eq("geo_code", data.geo)
        .eq("dimension_type", "totalt")
        .order("period")
        .order("dimension_value")
        .range(offset, offset + 999);
      if (page.error) throw new Error("Kunde inte läsa tidsserien.");
      rows.push(...(page.data ?? []));
      if ((page.data?.length ?? 0) < 1000) return rows;
    }
    throw new Error("Tidsserien kunde inte läsas fullständigt.");
  });
export const getAfDurationGroups = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) =>
    z.object({ geo, period: z.string().regex(/^\d{4}-\d{2}$/) }).parse(input),
  )
  .handler(async ({ data }): Promise<DurationRow[]> => {
    const result = await publicClient()
      .from("agg_af_duration")
      .select(fields)
      .eq("geo_code", data.geo)
      .eq("period", data.period)
      .order("dimension_type")
      .order("dimension_value")
      .limit(500);
    if (result.error) throw new Error("Kunde inte läsa grupperna.");
    if ((result.data?.length ?? 0) >= 500) throw new Error("Gruppurvalet är för stort.");
    return result.data ?? [];
  });
export const getAfDurationComparison = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) =>
    z.object({ period: z.string().regex(/^\d{4}-\d{2}$/) }).parse(input),
  )
  .handler(async ({ data }): Promise<DurationRow[]> => {
    const result = await publicClient()
      .from("agg_af_duration")
      .select(fields)
      .eq("period", data.period)
      .eq("dimension_type", "totalt")
      .order("geo_code")
      .limit(500);
    if (result.error) throw new Error("Kunde inte läsa geografijämförelsen.");
    if ((result.data?.length ?? 0) >= 500) throw new Error("Geografijämförelsen är för stor.");
    return result.data ?? [];
  });
