import { z } from "zod";
import { authorize, createRateLimiter, json } from "./etl-auth.server";

const stateRate = createRateLimiter(60);
const noChangeRate = createRateLimiter(60);

export async function handleEtlState(request: Request): Promise<Response> {
  if (request.method !== "GET") return json({ error: "Method not allowed" }, 405);
  const denied = await authorize(request);
  if (denied) return denied;
  if (stateRate()) return json({ error: "Too many requests" }, 429);

  const url = new URL(request.url);
  const parsed = z.string().min(1).max(100).safeParse(url.searchParams.get("indicator_id"));
  if (!parsed.success) return json({ error: "Invalid indicator_id" }, 400);

  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

  const { data: indicator, error: indicatorError } = await supabaseAdmin
    .from("indicators")
    .select("id, styrande_kalla, source_table_id")
    .eq("id", parsed.data)
    .maybeSingle();

  if (indicatorError) {
    console.error("[etl-state] indikatoruppslag misslyckades:", indicatorError.message);
    return json({ error: "Lookup failed" }, 500);
  }
  if (!indicator) return json({ error: "Unknown indicator" }, 404);

  const { data: metadata, error: metadataError } = await supabaseAdmin
    .from("indicator_metadata")
    .select("kalla_uppdaterad_datum, hamtad_datum, tillganglighetsdatum, styrande_kalla")
    .eq("indicator_id", parsed.data)
    .maybeSingle();

  if (metadataError) {
    console.error("[etl-state] metadatauppslag misslyckades:", metadataError.message);
    return json({ error: "Lookup failed" }, 500);
  }

  const { data: latestSuccessfulRun, error: runError } = await supabaseAdmin
    .from("data_source_runs")
    .select("finished_at")
    .eq("indicator_id", parsed.data)
    .eq("status", "succeeded")
    .not("finished_at", "is", null)
    .order("finished_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (runError) {
    console.error("[etl-state] uppslag av senaste lyckade körning misslyckades:", runError.message);
    return json({ error: "Lookup failed" }, 500);
  }

  return json(
    {
      indicator_id: indicator.id,
      source_table_id: indicator.source_table_id,
      styrande_kalla: metadata?.styrande_kalla ?? indicator.styrande_kalla,
      kalla_uppdaterad_datum: metadata?.kalla_uppdaterad_datum ?? null,
      hamtad_datum: metadata?.hamtad_datum ?? null,
      tillganglighetsdatum: metadata?.tillganglighetsdatum ?? null,
      last_successful_at: latestSuccessfulRun?.finished_at ?? null,
    },
    200,
  );
}

export async function handleEtlNoChange(request: Request): Promise<Response> {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const denied = await authorize(request);
  if (denied) return denied;
  if (noChangeRate()) return json({ error: "Too many requests" }, 429);

  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const parsed = z
    .object({
      indicator_id: z.string().min(1).max(100),
      source: z.string().min(1).max(100),
    })
    .safeParse(raw);

  if (!parsed.success) return json({ error: "Invalid payload" }, 400);

  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data: indicator, error: lookupError } = await supabaseAdmin
    .from("indicators")
    .select("id")
    .eq("id", parsed.data.indicator_id)
    .maybeSingle();

  if (lookupError) return json({ error: "Lookup failed" }, 500);
  if (!indicator) return json({ error: "Unknown indicator" }, 404);

  const now = new Date().toISOString();
  const { error } = await supabaseAdmin.from("data_source_runs").insert({
    source: parsed.data.source,
    indicator_id: parsed.data.indicator_id,
    status: "no_change",
    started_at: now,
    finished_at: now,
    rows_affected: 0,
  });

  if (error) {
    console.error("[etl-no-change] loggning misslyckades:", error.message);
    return json({ error: "Logging failed" }, 500);
  }

  return json({ status: "no_change", indicator_id: parsed.data.indicator_id }, 200);
}
