import { createServerFn } from "@tanstack/react-start";
import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import type { Database } from "@/integrations/supabase/types";

/**
 * Publik läsning av förberäknade aggregat (Riket, alla län, alla kommuner).
 * Aggregaten räknas om i databasen när en källa fått ny publicerad data.
 * Läs aldrig råa observationer härifrån.
 */

function publicClient() {
  const url = process.env["SUPABASE_URL"]!;
  const key = process.env["SUPABASE_PUBLISHABLE_KEY"]!;
  return createClient<Database>(url, key, {
    auth: { persistSession: false },
    global: {
      fetch: (input, init) => {
        const headers = new Headers(init?.headers);
        if (key.startsWith("sb_") && headers.get("Authorization") === `Bearer ${key}`) {
          headers.delete("Authorization");
        }
        headers.set("apikey", key);
        return fetch(input, { ...init, headers });
      },
    },
  });
}

const geo = z.string().regex(/^(00|\d{2}|\d{4})$/);

export const getAfTotals = createServerFn({ method: "GET" })
  .inputValidator((d: unknown) =>
    z
      .object({ indicatorId: z.string().regex(/^af-/), geo, sex: z.string().max(1).default("") })
      .parse(d),
  )
  .handler(async ({ data }) => {
    const { data: rows, error } = await publicClient()
      .from("agg_af_totals")
      .select("measure_code, measure_label, period, value")
      .eq("indicator_id", data.indicatorId)
      .eq("geo_code", data.geo)
      .eq("sex", data.sex)
      .order("period")
      .limit(5000);
    if (error) throw new Error("Kunde inte läsa AF-statistik");
    return rows ?? [];
  });

export const getAfrStructure = createServerFn({ method: "GET" })
  .inputValidator((d: unknown) => z.object({ geo }).parse(d))
  .handler(async ({ data }) => {
    const { data: rows, error } = await publicClient()
      .from("agg_afr_ae_structure")
      .select("sni_avdelning, sni2, anst_kl, arbetsstallen")
      .eq("geo_code", data.geo)
      .limit(10000);
    if (error) throw new Error("Kunde inte läsa näringslivsstruktur");
    return rows ?? [];
  });

export const getE3Matchning = createServerFn({ method: "GET" })
  .inputValidator((d: unknown) => z.object({ geo, period: z.string().regex(/^\d{4}$/) }).parse(d))
  .handler(async ({ data }) => {
    const { data: rows, error } = await publicClient()
      .from("agg_e3_matchning")
      .select(
        "utbildning_code, utbildning_label, sni_code, sni_label, helt, delvis, inte, saknas, totalt",
      )
      .eq("geo_code", data.geo)
      .eq("period", data.period)
      .limit(20000);
    if (error) throw new Error("Kunde inte läsa matchningsstatistik");
    return rows ?? [];
  });

const ukaIds = [
  "uka-forstahandssokande-yrkesprogram",
  "uka-antagna-yrkesprogram",
  "uka-soktryck-yrkesprogram",
  "uka-nyborjare-yrkesprogram",
  "uka-hst",
  "uka-examinerade",
  "uka-etablering",
] as const;

// Läs alla sidor: PostgREST kan begränsa varje svar till 1 000 rader.
export const getUkaUniversities = createServerFn({ method: "GET" }).handler(async () => {
  const client = publicClient();
  const universities = new Set<string>();
  for (let offset = 0; offset < 20000; offset += 1000) {
    const { data: rows, error } = await client
      .from("agg_uka_university")
      .select("university, indicator_id, period")
      .in("indicator_id", [...ukaIds])
      .eq("breakdown", "")
      .eq("gender", "Total")
      .order("university")
      .order("indicator_id")
      .order("period")
      .range(offset, offset + 999);
    if (error) throw new Error("Kunde inte läsa UKÄ:s lärosäten. Försök igen.");
    for (const row of rows ?? []) universities.add(row.university);
    if ((rows?.length ?? 0) < 1000)
      return [...universities].sort((a, b) => a.localeCompare(b, "sv"));
  }
  throw new Error("UKÄ:s lärosäteslista kunde inte läsas fullständigt.");
});

export const getUkaEducation = createServerFn({ method: "GET" })
  .inputValidator((d: unknown) =>
    z.object({ university: z.string().trim().min(1).max(200) }).parse(d),
  )
  .handler(async ({ data }) => {
    const client = publicClient();
    const result: Database["public"]["Tables"]["agg_uka_university"]["Row"][] = [];
    for (let offset = 0; offset < 50000; offset += 1000) {
      const { data: rows, error } = await client
        .from("agg_uka_university")
        .select("indicator_id, university, period, gender, breakdown, category, value")
        .in("indicator_id", [...ukaIds])
        .eq("university", data.university)
        .order("indicator_id")
        .order("period")
        .order("gender")
        .order("breakdown")
        .order("category")
        .range(offset, offset + 999);
      if (error) throw new Error("Kunde inte läsa UKÄ-statistiken. Försök igen.");
      result.push(...(rows ?? []));
      if ((rows?.length ?? 0) < 1000) {
        const { data: metadata, error: metadataError } = await client
          .from("indicator_metadata")
          .select("indicator_id, tillganglighetsdatum, hamtad_datum")
          .in("indicator_id", [...ukaIds]);
        if (metadataError) throw new Error("Kunde inte läsa UKÄ:s metadata. Försök igen.");
        return { rows: result, metadata: metadata ?? [] };
      }
    }
    throw new Error("UKÄ-urvalet är för stort för att visas fullständigt.");
  });
