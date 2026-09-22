import { createServerFn } from "@tanstack/react-start";
import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import type { Database } from "@/integrations/supabase/types";
import type { Indicator } from "@/data/types";

/**
 * Serverfunktioner som läser indikatorer från databasen.
 * Publik läsning via publishable-nyckeln — RLS i databasen avgör vad som syns
 * (publik / inloggad / admin). Ingen extern datakälla anropas vid sidladdning.
 */

function createPublicClient() {
  const url = process.env["SUPABASE_URL"]!;
  const key = process.env["SUPABASE_PUBLISHABLE_KEY"]!;
  return createClient<Database>(url, key, {
    auth: { persistSession: false },
    // sb_-nycklar är inte JWT:er — skicka bara apikey, inte Authorization: Bearer.
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

type IndicatorRow = Database["public"]["Tables"]["indicators"]["Row"];
type MetadataRow = Database["public"]["Tables"]["indicator_metadata"]["Row"];
type ObservationRow = Database["public"]["Tables"]["observations"]["Row"];
type GeographyRow = Database["public"]["Tables"]["geographies"]["Row"];

function toIndicator(
  row: IndicatorRow,
  metadata: MetadataRow | undefined,
  observations: ObservationRow[],
  geographies: Map<string, GeographyRow>,
): Indicator {
  // Antagande i iterationens datamodell: en geografi per indikator (första i serien).
  const geoCode = observations[0]?.geo_code;
  const geo = geoCode ? geographies.get(geoCode) : undefined;
  return {
    id: row.id,
    name: row.name,
    description: row.description,
    unit: row.unit,
    metadata: {
      source: metadata?.kalla ?? row.styrande_kalla,
      updatedAt:
        metadata?.tillganglighetsdatum ??
        metadata?.hamtad_datum ??
        metadata?.kalla_uppdaterad_datum ??
        "",
      geoLevel: geo?.level ?? "län",
      area: geo?.name ?? "",
      period: metadata?.period ?? "",
      isExample: row.is_example,
    },
    series: observations
      .map((o) => ({ label: o.period, value: o.value ?? 0 }))
      .sort((a, b) => a.label.localeCompare(b.label)),
  };
}

async function fetchIndicators(
  supabase: ReturnType<typeof createPublicClient>,
  id?: string,
): Promise<Indicator[]> {
  let query = supabase.from("indicators").select("*").order("name");
  if (id) {
    query = query.eq("id", id);
  } else {
    // Statistik-sidan är fortfarande en presentationsyta för exempel.
    // Råa E3-observationer är flerdimensionella och får en egen läsmodell
    // innan de visas i gränssnittet.
    query = query.eq("is_example", true);
  }
  const { data: rows, error } = await query;
  if (error) throw new Error(`Kunde inte läsa indikatorer: ${error.message}`);
  if (!rows?.length) return [];

  const ids = rows.map((r) => r.id);
  const [{ data: metadata }, { data: observations }, { data: geos }] = await Promise.all([
    supabase.from("indicator_metadata").select("*").in("indicator_id", ids),
    supabase.from("observations").select("*").in("indicator_id", ids),
    supabase.from("geographies").select("*"),
  ]);

  const metadataByIndicator = new Map((metadata ?? []).map((m) => [m.indicator_id, m]));
  const geoByCode = new Map((geos ?? []).map((g) => [g.code, g]));

  return rows.map((row) =>
    toIndicator(
      row,
      metadataByIndicator.get(row.id),
      (observations ?? []).filter((o) => o.indicator_id === row.id),
      geoByCode,
    ),
  );
}

export const listIndicatorsFn = createServerFn({ method: "GET" }).handler(async () => {
  return fetchIndicators(createPublicClient());
});

export const getIndicatorFn = createServerFn({ method: "GET" })
  .inputValidator((data: unknown) => z.object({ id: z.string() }).parse(data))
  .handler(async ({ data }) => {
    const indicators = await fetchIndicators(createPublicClient(), data.id);
    return indicators[0];
  });
