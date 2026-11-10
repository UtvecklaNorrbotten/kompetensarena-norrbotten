import { createServerFn } from "@tanstack/react-start";
import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import type { Database } from "@/integrations/supabase/types";
import {
  UKA_SLICE_MAX_PAGES,
  UKA_SLICE_PAGE_ROWS,
  type UkaEducationCatalog,
  type UkaSlicePage,
} from "@/lib/uka-education";

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

// Utbildningssidan läser aldrig hela lärosätet i ett svar (Riket har >100 000 HST-rader).
// Katalogen beskriver perioder, uppdelningar och kategorier; värden hämtas per figur,
// uppdelning och urval i begränsade sidor.
const university = z.string().trim().min(1).max(200);
const MAX_CATALOG_COMBOS = 50000;

export const getUkaEducationCatalog = createServerFn({ method: "GET" })
  .inputValidator((d: unknown) => z.object({ university }).parse(d))
  .handler(async ({ data }): Promise<UkaEducationCatalog> => {
    const client = publicClient();
    const [{ data: catalog, error }, { data: metadata, error: metadataError }] = await Promise.all([
      client.rpc("uka_education_catalog", {
        p_university: data.university,
        p_indicator_ids: [...ukaIds],
      }),
      client
        .from("indicator_metadata")
        .select("indicator_id, tillganglighetsdatum, hamtad_datum")
        .in("indicator_id", [...ukaIds]),
    ]);
    if (error) throw new Error("Kunde inte läsa UKÄ-statistiken. Försök igen.");
    if (metadataError) throw new Error("Kunde inte läsa UKÄ:s metadata. Försök igen.");
    const parsed = catalog as {
      indicators?: UkaEducationCatalog["indicators"];
      combos?: [string, string][];
    } | null;
    const pairs = parsed?.combos ?? [];
    if (pairs.length > MAX_CATALOG_COMBOS) {
      throw new Error("UKÄ:s urvalskatalog är för stor för att visas fullständigt.");
    }
    const combos: UkaEducationCatalog["combos"] = {};
    for (const [breakdown, category] of pairs) (combos[breakdown] ??= []).push(category);
    return { indicators: parsed?.indicators ?? {}, combos, metadata: metadata ?? [] };
  });

const dimensionKey = z.string().regex(/^[a-z-]{1,40}$/);

export const getUkaEducationSlice = createServerFn({ method: "GET" })
  .inputValidator((d: unknown) =>
    z
      .object({
        university,
        indicatorId: z.enum(ukaIds),
        breakdown: z.string().regex(/^([a-z-]{1,40}(\|[a-z-]{1,40}){0,7})?$/),
        selection: z.record(dimensionKey, z.string().min(1).max(300)).refine(
          (s) => Object.keys(s).length <= 8,
        ),
        offset: z.number().int().min(0).max(UKA_SLICE_PAGE_ROWS * UKA_SLICE_MAX_PAGES),
      })
      .parse(d),
  )
  .handler(async ({ data }): Promise<UkaSlicePage> => {
    const client = publicClient();
    const rows: UkaSlicePage["rows"] = [];
    // Databasen ger högst 1 000 rader per anrop; svaret begränsas till UKA_SLICE_PAGE_ROWS.
    for (let offset = data.offset; offset < data.offset + UKA_SLICE_PAGE_ROWS; offset += 1000) {
      const { data: page, error } = await client.rpc("uka_education_slice", {
        p_university: data.university,
        p_indicator_id: data.indicatorId,
        p_breakdown: data.breakdown,
        p_selection: data.selection,
        p_offset: offset,
        p_limit: 1000,
      });
      if (error) throw new Error("Kunde inte läsa UKÄ-statistiken. Försök igen.");
      rows.push(...(page ?? []));
      if ((page?.length ?? 0) < 1000) return { rows, next: null };
    }
    return { rows, next: data.offset + UKA_SLICE_PAGE_ROWS };
  });
