import { z } from "zod";
import { authorize, createRateLimiter, json } from "./etl-auth.server";

const MAX_BODY_BYTES = 6_000_000;
const MAX_RECORDS_PER_CHUNK = 5_000;
const controlRate = createRateLimiter(60);
const chunkRate = createRateLimiter(300);

const observationSchema = z.object({
  period: z.string().min(1).max(20),
  university: z.string().min(1).max(300),
  gender: z.string().max(50).nullable().optional(),
  value: z.number().finite().nullable().optional(),
  dimensions: z.record(z.string(), z.union([z.string(), z.number(), z.boolean()])).optional(),
}).strict();

const startSchema = z.object({
  indicator_id: z.string().regex(/^uka-/),
  source: z.string().min(1).max(100),
  expected_chunks: z.number().int().min(1).max(10000),
  expected_rows: z.number().int().min(0),
  kalla_uppdaterad_datum: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
});

const chunkSchema = z.object({
  batch_id: z.string().uuid(),
  indicator_id: z.string().regex(/^uka-/),
  chunk_index: z.number().int().min(0).max(9999),
  observations: z.array(observationSchema).min(1).max(MAX_RECORDS_PER_CHUNK),
});

const finalizeSchema = z.object({ batch_id: z.string().uuid() });
const abortSchema = z.object({
  batch_id: z.string().uuid(),
  reason: z.string().max(500).optional(),
});

async function admin() {
  return (await import("@/integrations/supabase/client.server")).supabaseAdmin;
}

async function readBody<T>(
  request: Request,
  schema: z.ZodType<T>,
): Promise<{ ok: true; data: T } | { ok: false; response: Response }> {
  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) return { ok: false, response: json({ error: "Payload too large" }, 413) };
  let value: unknown;
  try { value = JSON.parse(raw); } catch { return { ok: false, response: json({ error: "Invalid JSON" }, 400) }; }
  const parsed = schema.safeParse(value);
  if (!parsed.success) {
    return {
      ok: false,
      response: json({ error: "Invalid payload", issues: parsed.error.issues.slice(0,20).map(i => ({ path: i.path, message: i.message })) }, 400),
    };
  }
  return { ok: true, data: parsed.data };
}

async function guard(request: Request, method: string, rate: () => boolean) {
  if (request.method !== method) return json({ error: "Method not allowed" }, 405);
  const denied = await authorize(request);
  if (denied) return denied;
  if (rate()) return json({ error: "Too many requests" }, 429);
  return null;
}

function statusFor(error: { code?: string; message: string }) {
  if (/timeout|timed out|fetch failed|connection/i.test(error.message)) return 503;
  if (["57014","55P03","40P01","40001"].includes(error.code ?? "")) return 503;
  if (error.code === "02000") return 404;
  if (["23505","22023"].includes(error.code ?? "")) return 409;
  return 422;
}

export async function handleUkaStart(request: Request) {
  const denied = await guard(request, "POST", controlRate);
  if (denied) return denied;
  const body = await readBody(request, startSchema);
  if (!body.ok) return body.response;
  const p = body.data;
  const db = await admin();

  const { data: indicator } = await db.from("indicators").select("id").eq("id", p.indicator_id).maybeSingle();
  if (!indicator) return json({ error: "Unknown indicator" }, 404);

  const { data: run, error: runError } = await db.from("data_source_runs").insert({
    source: p.source,
    source_id: "uka-hogskolan-i-siffror",
    indicator_id: p.indicator_id,
    status: "started",
    started_at: new Date().toISOString(),
  }).select("id").single();
  if (runError) return json({ error: "Run log failed" }, 500);

  const { data, error } = await (db.rpc as any)("uka_start_batch", {
    p_indicator_id: p.indicator_id,
    p_source: p.source,
    p_expected_chunks: p.expected_chunks,
    p_expected_rows: p.expected_rows,
    ...(p.kalla_uppdaterad_datum ? { p_kalla_uppdaterad_datum: p.kalla_uppdaterad_datum } : {}),
    ...(run?.id ? { p_run_id: run.id } : {}),
  });
  if (error) return json({ error: "UKA start failed", message: error.message }, statusFor(error));
  return json({ batch_id: data, indicator_id: p.indicator_id }, 200);
}

export async function handleUkaChunk(request: Request) {
  const denied = await guard(request, "POST", chunkRate);
  if (denied) return denied;
  const body = await readBody(request, chunkSchema);
  if (!body.ok) return body.response;
  const p = body.data;
  const { createHash } = await import("node:crypto");
  const checksum = createHash("sha256").update(JSON.stringify(p.observations), "utf8").digest("hex");
  const db = await admin();
  const { data, error } = await (db.rpc as any)("uka_store_chunk", {
    p_batch_id: p.batch_id,
    p_indicator_id: p.indicator_id,
    p_chunk_index: p.chunk_index,
    p_observations: p.observations,
    p_checksum: checksum,
  });
  if (error) return json({ error: "UKA chunk failed", message: error.message }, statusFor(error));
  return json(data, 200);
}

export async function handleUkaFinalize(request: Request) {
  const denied = await guard(request, "POST", controlRate);
  if (denied) return denied;
  const body = await readBody(request, finalizeSchema);
  if (!body.ok) return body.response;
  const db = await admin();
  const { data, error } = await (db.rpc as any)("uka_finalize_batch", { p_batch_id: body.data.batch_id });
  if (error) return json({ error: "UKA finalize failed", message: error.message }, statusFor(error));
  // En lyckad publicering ska även göra de nya värdena tillgängliga för figurerna.
  // Finalisering är idempotent: om omräkningen misslyckas kan ETL göra om anropet.
  const { error: refreshError } = await db.rpc("agg_refresh_uka");
  if (refreshError) return json({ error: "UKA aggregate refresh failed", message: refreshError.message }, 503);
  return json(data, 200);
}

export async function handleUkaAbort(request: Request) {
  const denied = await guard(request, "POST", controlRate);
  if (denied) return denied;
  const body = await readBody(request, abortSchema);
  if (!body.ok) return body.response;
  const db = await admin();
  const { data, error } = await (db.rpc as any)("uka_abort_batch", {
    p_batch_id: body.data.batch_id,
    ...(body.data.reason ? { p_reason: body.data.reason } : {}),
  });
  if (error) return json({ error: "UKA abort failed", message: error.message }, statusFor(error));
  return json(data, 200);
}

