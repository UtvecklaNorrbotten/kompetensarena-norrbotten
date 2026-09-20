/**
 * ETL-endpointens serverlogik.
 *
 * Tar emot ett färdigvaliderat dataset från ETL-jobbet (GitHub Actions + R),
 * validerar payloaden strikt och publicerar den atomiskt via databasfunktionen
 * `publish_indicator`. Endpointen kan inte göra något annat: ingen generell
 * databasåtkomst, inga adminfunktioner, ingen SQL utifrån.
 *
 * Autentisering: delad hemlighet i `ETL_PUBLISH_KEY` (och valfritt
 * `ETL_PUBLISH_KEY_PREVIOUS` under nyckelbyte). Nyckeln finns bara som
 * hemlighet i Lovable och i GitHub Actions Secrets — aldrig i repot, aldrig i
 * frontend och aldrig i loggar.
 */
import { z } from "zod";
import { authorize, createRateLimiter, json } from "./etl-auth.server";

const MAX_BODY_BYTES = 2_000_000; // ~2 MB
const RATE_LIMIT_MAX = 12; // anrop per fönster och instans

const observationSchema = z.object({
  geo_code: z.string().min(1).max(20),
  period: z.string().min(1).max(20),
  value: z.number().finite().nullable().optional(),
  dimensions: z.record(z.string(), z.union([z.string(), z.number(), z.boolean()])).optional(),
});

const payloadSchema = z.object({
  indicator_id: z.string().min(1).max(100),
  source: z.string().min(1).max(100),
  kalla_uppdaterad_datum: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "Datum måste vara YYYY-MM-DD")
    .optional(),
  observations: z.array(observationSchema).min(1).max(50_000),
});

export type EtlPayload = z.infer<typeof payloadSchema>;

// Enkel takbegränsning per serverinstans (best effort — den riktiga
// samtidighetsspärren är advisory lock per indikator i publish_indicator).
const rateLimited = createRateLimiter(RATE_LIMIT_MAX);

export async function handleEtlPublish(request: Request): Promise<Response> {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const denied = await authorize(request);
  if (denied) return denied;

  if (rateLimited()) return json({ error: "Too many requests" }, 429);

  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) return json({ error: "Payload too large" }, 413);

  let parsedJson: unknown;
  try {
    parsedJson = JSON.parse(raw);
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const parsed = payloadSchema.safeParse(parsedJson);
  if (!parsed.success) {
    return json(
      { error: "Invalid payload", issues: parsed.error.issues.map((i) => ({ path: i.path, message: i.message })) },
      400,
    );
  }
  const payload = parsed.data;

  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

  // Okänd indikator avvisas innan något skrivs.
  const { data: indicator, error: lookupError } = await supabaseAdmin
    .from("indicators")
    .select("id")
    .eq("id", payload.indicator_id)
    .maybeSingle();
  if (lookupError) {
    console.error("[etl] uppslag av indikator misslyckades:", lookupError.message);
    return json({ error: "Lookup failed" }, 500);
  }
  if (!indicator) return json({ error: "Unknown indicator" }, 404);

  const startedAt = new Date().toISOString();
  const { data: run } = await supabaseAdmin
    .from("data_source_runs")
    .insert({
      source: payload.source,
      indicator_id: payload.indicator_id,
      status: "started",
      started_at: startedAt,
    })
    .select("id")
    .single();

  const finish = async (
    status: "succeeded" | "failed",
    rows: number | null,
    errorMessage: string | null,
  ) => {
    if (!run) return;
    await supabaseAdmin
      .from("data_source_runs")
      .update({
        status,
        finished_at: new Date().toISOString(),
        rows_affected: rows,
        error_message: errorMessage,
      })
      .eq("id", run.id);
  };

  // Publicering sker enbart via publish_indicator — allt eller inget.
  const { data: result, error: publishError } = await supabaseAdmin.rpc("publish_indicator", {
    p_indicator_id: payload.indicator_id,
    p_observations: payload.observations,
    ...(payload.kalla_uppdaterad_datum
      ? { p_kalla_uppdaterad_datum: payload.kalla_uppdaterad_datum }
      : {}),
    p_rows_affected: payload.observations.length,
  });

  if (publishError) {
    console.error("[etl] publicering misslyckades:", publishError.message);
    await finish("failed", null, publishError.message);
    return json({ error: "Publish failed", message: publishError.message }, 422);
  }

  const rows =
    result && typeof result === "object" && "rows" in result ? Number((result as { rows: unknown }).rows) : null;
  await finish("succeeded", rows, null);

  return json({ status: "succeeded", indicator_id: payload.indicator_id, rows }, 200);
}
