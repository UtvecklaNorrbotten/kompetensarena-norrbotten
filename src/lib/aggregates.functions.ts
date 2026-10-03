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
    z.object({ indicatorId: z.string().regex(/^af-/), geo, sex: z.string().max(1).default("") }).parse(d),
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
      .select("utbildning_code, utbildning_label, sni_code, sni_label, helt, delvis, inte, saknas, totalt")
      .eq("geo_code", data.geo)
      .eq("period", data.period)
      .limit(20000);
    if (error) throw new Error("Kunde inte läsa matchningsstatistik");
    return rows ?? [];
  });
