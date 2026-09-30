/**
 * Chunkad ETL-import med staging och atomisk finalisering.
 *
 * Komplement till `/api/public/jobs/publish-indicator` för stora dataset
 * (t.ex. SCB TAB6929/E3) som inte får plats i ett enda anrop.
 *
 * Flöde: start -> chunk (1..n) -> finalize. Vid avbrott: abort.
 * All publicering sker i databasfunktionen `etl_finalize_batch`, som tar
 * advisory lock per indikator och ersätter data i en enda transaktion.
 * Endpointen ger ingen generell databasåtkomst och inga adminfunktioner.
 */
import { z } from "zod";
import { authorize, createRateLimiter, json } from "./etl-auth.server";

const MAX_BODY_BYTES = 6_000_000; // ~6 MB per chunk-anrop
const MAX_OBS_PER_CHUNK = 20_000;
const MAX_CHUNKS = 2_000;

const controlRate = createRateLimiter(30);
const chunkRate = createRateLimiter(240);

const observationSchema = z.object({
  geo_code: z.string().min(1).max(20),
  period: z.string().min(1).max(20),
  value: z.number().finite().nullable().optional(),
  dimensions: z.record(z.string(), z.union([z.string(), z.number(), z.boolean()])).optional(),
});

const startSchema = z
  .object({
    indicator_id: z.string().min(1).max(100),
    source: z.string().min(1).max(100),
    expected_chunks: z.number().int().min(1).max(MAX_CHUNKS),
    expected_rows: z.number().int().min(0).optional(),
    mode: z.enum(["full", "replace_period"]).default("full"),
    replace_period: z.string().min(1).max(20).optional(),
    kalla_uppdaterad_datum: z
      .string()
      .regex(/^\d{4}-\d{2}-\d{2}$/, "Datum måste vara YYYY-MM-DD")
      .optional(),
  })
  .superRefine((value, ctx) => {
    if (value.mode === "replace_period" && !value.replace_period) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["replace_period"],
        message: "replace_period krävs i replace_period-läge",
      });
    }
    if (value.mode === "replace_period" && value.expected_rows === undefined) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["expected_rows"],
        message: "expected_rows krävs i replace_period-läge",
      });
    }
  });

const chunkSchema = z.object({
  batch_id: z.string().uuid(),
  indicator_id: z.string().min(1).max(100),
  chunk_index: z.number().int().min(0).max(MAX_CHUNKS - 1),
  observations: z.array(observationSchema).min(1).max(MAX_OBS_PER_CHUNK),
});

const finalizeSchema = z.object({ batch_id: z.string().uuid() });
const abortSchema = z.object({ batch_id: z.string().uuid(), reason: z.string().max(500).optional() });
const cleanupSchema = z.object({
  batch_id: z.string().uuid(),
  max_rows: z.number().int().min(1).max(50000).default(5000),
});

type PgError = { code?: string; message: string };

/** Översätter databasens felkoder till HTTP-status utan att läcka interna detaljer. */
function statusForPgError(error: PgError): number {
  switch (error.code) {
    case "57014": // query_canceled (statement timeout)
    case "55P03": // lock_not_available (lock timeout)
    case "40P01": // deadlock_detected
    case "40001": // serialization_failure
      return 503;
    case "02000": // no_data_found -> okänd batch/indikator
      return 404;
    case "23505": // unique_violation -> dubblerad chunk med annat innehåll
      return 409;
    case "22023": // invalid_parameter_value -> fel tillstånd/index/radantal
      return 409;
    case "23503": // foreign_key_violation -> okänd geografi
      return 422;
    default:
      return 422;
  }
}

async function readBody<T>(
  request: Request,
  schema: z.ZodType<T>,
): Promise<{ ok: true; data: T } | { ok: false; response: Response }> {
  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) return { ok: false, response: json({ error: "Payload too large" }, 413) };

  let parsedJson: unknown;
  try {
    parsedJson = JSON.parse(raw);
  } catch {
    return { ok: false, response: json({ error: "Invalid JSON" }, 400) };
  }

  const parsed = schema.safeParse(parsedJson);
  if (!parsed.success) {
    return {
      ok: false,
      response: json(
        {
          error: "Invalid payload",
          issues: parsed.error.issues.map((i) => ({ path: i.path, message: i.message })),
        },
        400,
      ),
    };
  }
  return { ok: true, data: parsed.data };
}

async function guard(request: Request, rateLimited: () => boolean): Promise<Response | null> {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const denied = await authorize(request);
  if (denied) return denied;
  if (rateLimited()) return json({ error: "Too many requests" }, 429);
  return null;
}

/** POST /api/public/jobs/etl-batch/start */
export async function handleBatchStart(request: Request): Promise<Response> {
  const denied = await guard(request, controlRate);
  if (denied) return denied;

  const body = await readBody(request, startSchema);
  if (!body.ok) return body.response;
  const payload = body.data;

  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

  const { data: indicator, error: lookupError } = await supabaseAdmin
    .from("indicators")
    .select("id")
    .eq("id", payload.indicator_id)
    .maybeSingle();
  if (lookupError) {
    console.error("[etl-batch] uppslag av indikator misslyckades:", lookupError.message);
    return json({ error: "Lookup failed" }, 500);
  }
  if (!indicator) return json({ error: "Unknown indicator" }, 404);

  const { data: run } = await supabaseAdmin
    .from("data_source_runs")
    .insert({
      source: payload.source,
      indicator_id: payload.indicator_id,
      status: "started",
      started_at: new Date().toISOString(),
    })
    .select("id")
    .single();

  const rpcResult =
    payload.mode === "replace_period"
      ? await supabaseAdmin.rpc("etl_start_period_batch", {
          p_indicator_id: payload.indicator_id,
          p_source: payload.source,
          p_replace_period: payload.replace_period!,
          p_expected_chunks: payload.expected_chunks,
          p_expected_rows: payload.expected_rows!,
          ...(payload.kalla_uppdaterad_datum
            ? { p_kalla_uppdaterad_datum: payload.kalla_uppdaterad_datum }
            : {}),
          ...(run?.id ? { p_run_id: run.id } : {}),
        })
      : await supabaseAdmin.rpc("etl_start_batch", {
          p_indicator_id: payload.indicator_id,
          p_source: payload.source,
          p_expected_chunks: payload.expected_chunks,
          ...(payload.expected_rows !== undefined ? { p_expected_rows: payload.expected_rows } : {}),
          ...(payload.kalla_uppdaterad_datum
            ? { p_kalla_uppdaterad_datum: payload.kalla_uppdaterad_datum }
            : {}),
          ...(run?.id ? { p_run_id: run.id } : {}),
        });

  const { data: batchId, error } = rpcResult;

  if (error) {
    console.error("[etl-batch] kunde inte starta batch:", error.message);
    return json({ error: "Batch start failed", message: error.message }, statusForPgError(error));
  }

  return json(
    {
      batch_id: batchId,
      indicator_id: payload.indicator_id,
      expected_chunks: payload.expected_chunks,
      expected_rows: payload.expected_rows ?? null,
      mode: payload.mode,
      replace_period: payload.replace_period ?? null,
      status: "started",
    },
    200,
  );
}

/** POST /api/public/jobs/etl-batch/chunk */
export async function handleBatchChunk(request: Request): Promise<Response> {
  const denied = await guard(request, chunkRate);
  if (denied) return denied;

  const body = await readBody(request, chunkSchema);
  if (!body.ok) return body.response;
  const payload = body.data;

  // Checksumma för idempotens: samma chunk två gånger med identiskt innehåll
  // accepteras, annat innehåll på samma index avvisas.
  const { createHash } = await import("node:crypto");
  const checksum = createHash("sha256").update(JSON.stringify(payload.observations), "utf8").digest("hex");

  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const rpcStarted = performance.now();
  const { data, error } = await supabaseAdmin.rpc("etl_store_chunk", {
    p_batch_id: payload.batch_id,
    p_indicator_id: payload.indicator_id,
    p_chunk_index: payload.chunk_index,
    p_observations: payload.observations,
    p_checksum: checksum,
  });
  // Inkluderar transporten till PostgREST, inte enbart SQL-exekvering.
  const rpcMs = Math.round(performance.now() - rpcStarted);
  console.info("[etl-batch] chunk RPC", {
    batch_id: payload.batch_id,
    chunk_index: payload.chunk_index,
    rows: payload.observations.length,
    rpc_ms: rpcMs,
    error_code: error?.code ?? null,
  });

  if (error) {
    console.error("[etl-batch] chunk avvisad:", error.message);
    return json({ error: "Chunk rejected", message: error.message, code: error.code, rpc_ms: rpcMs }, statusForPgError(error));
  }

  return json({ ...(data as Record<string, unknown>), rpc_ms: rpcMs }, 200);
}

/** POST /api/public/jobs/etl-batch/finalize */
export async function handleBatchFinalize(request: Request): Promise<Response> {
  const denied = await guard(request, controlRate);
  if (denied) return denied;

  const body = await readBody(request, finalizeSchema);
  if (!body.ok) return body.response;

  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data, error } = await supabaseAdmin.rpc("etl_finalize_batch", { p_batch_id: body.data.batch_id });

  if (error) {
    console.error("[etl-batch] finalisering misslyckades:", error.message);
    // Transaktionen rullas tillbaka i databasen — publicerad data är oförändrad.
    await supabaseAdmin
      .from("etl_batches")
      .update({ error_message: error.message, last_activity_at: new Date().toISOString() })
      .eq("id", body.data.batch_id);
    return json({ error: "Finalize failed", message: error.message }, statusForPgError(error));
  }

  return json({ status: "succeeded", ...(data as Record<string, unknown>) }, 200);
}

/** POST /api/public/jobs/etl-batch/abort */
export async function handleBatchAbort(request: Request): Promise<Response> {
  const denied = await guard(request, controlRate);
  if (denied) return denied;

  const body = await readBody(request, abortSchema);
  if (!body.ok) return body.response;

  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data, error } = await supabaseAdmin.rpc("etl_abort_batch", {
    p_batch_id: body.data.batch_id,
    ...(body.data.reason ? { p_reason: body.data.reason } : {}),
  });

  if (error) {
    console.error("[etl-batch] avbrott misslyckades:", error.message);
    return json({ error: "Abort failed", message: error.message }, statusForPgError(error));
  }

  return json(data, 200);
}


/** POST /api/public/jobs/etl-batch/cleanup-failed
 * Tar bort en begränsad mängd observationsrader från en redan misslyckad,
 * osynlig batch. Klienten upprepar anropet tills remaining=false.
 */
export async function handleBatchCleanupFailed(request: Request): Promise<Response> {
  const denied = await guard(request, chunkRate);
  if (denied) return denied;

  const body = await readBody(request, cleanupSchema);
  if (!body.ok) return body.response;

  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data, error } = await supabaseAdmin.rpc("etl_cleanup_failed_batch", {
    p_batch_id: body.data.batch_id,
    p_max_rows: body.data.max_rows,
  });

  if (error) {
    console.error("[etl-batch] cleanup misslyckades:", error.message);
    return json(
      { error: "Cleanup failed", message: error.message, code: error.code },
      statusForPgError(error),
    );
  }

  return json(data, 200);
}
