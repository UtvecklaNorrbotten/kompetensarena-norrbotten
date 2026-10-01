/**
 * ETL-endpoints för SCB Allmänna företagsregistret (AFR).
 *
 * Endast GitHub Actions (ETL_PUBLISH_KEY) når dessa. All skrivning sker i
 * security definer-funktioner (afr_*) som bara service_role får anropa.
 * Posterna valideras strikt: okända fält (t.ex. telefon, e-post, adress)
 * avvisas så att de aldrig kan lagras av misstag.
 */
import { z } from "zod";
import type { Json } from "@/integrations/supabase/types";
import { authorize, createRateLimiter, json } from "./etl-auth.server";

const MAX_BODY_BYTES = 6_000_000;
const MAX_RECORDS_PER_CHUNK = 5_000;
const MAX_REMOVED_PER_CHUNK = 50_000;
const SOURCE_ID = "scb-afr";

const controlRate = createRateLimiter(60);
const chunkRate = createRateLimiter(300);
const readRate = createRateLimiter(600);

const str = (max: number) => z.string().max(max * 10).nullable();
const int = z.number().int().nullable();
const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable();
const hash = z.string().regex(/^[0-9a-f]{64}$/);

const sniSchema = z
  .object({
    r: z.number().int().min(0).max(1000),
    kod: z.string().min(1).max(50),
    andel: int,
    avd: str(10),
  })
  .strict();

const jeRecord = z
  .object({
    key: z.string().min(1).max(40),
    org_nr: str(40),
    kommun_sate: str(10),
    lan_sate: str(10),
    ae_ant: int,
    anst_kl: str(10),
    ftg_stat: str(10),
    jurform: str(10),
    start_dat: date,
    slut_dat: date,
    reg_dat: date,
    oms_ar: int,
    oms_kl: str(10),
    ag_kat: str(10),
    arb_giv_stat: str(10),
    moms_stat: str(10),
    f_skatt_stat: str(10),
    bol_stat: str(10),
    priv_publ: str(10),
    sektor: str(20),
    sni: z.array(sniSchema).max(1000),
    hash,
  })
  .strict();

const aeRecord = z
  .object({
    key: z.string().regex(/^\d{1,18}$/),
    pe_org_nr: str(40),
    ae_stat: int,
    anst_kl: int,
    hj_verks_je: int,
    ae_typ: int,
    start_dat: date,
    slut_dat: date,
    lan: str(10),
    kommun: str(10),
    nord_sw: int,
    ost_sw: int,
    tat_sma_typ_kod: str(20),
    tat_ort_sma_ort_kod: str(20),
    tat_ort_sma_ort_ben: str(200),
    sni: z.array(sniSchema).max(1000),
    hash,
  })
  .strict();

const startSchema = z.object({
  mode: z.enum(["initial", "daily"]),
  source_date: z.string().min(1).max(50),
  api_version: z.string().max(50).nullable().optional(),
  fetched_at: z.string().datetime({ offset: true }),
  je_source_count: z.number().int().min(0),
  ae_source_count: z.number().int().min(0),
  expected_je_chunks: z.number().int().min(0).max(2000),
  expected_ae_chunks: z.number().int().min(0).max(2000),
  confirm_large_removal: z.boolean().optional(),
  details: z.record(z.string(), z.unknown()).optional(),
});

const chunkSchema = z.discriminatedUnion("entity", [
  z.object({
    sync_id: z.string().uuid(),
    entity: z.literal("je"),
    chunk_index: z.number().int().min(0).max(1999),
    records: z.array(jeRecord).max(MAX_RECORDS_PER_CHUNK),
    removed: z.array(z.string().min(1).max(40)).max(MAX_REMOVED_PER_CHUNK).default([]),
  }),
  z.object({
    sync_id: z.string().uuid(),
    entity: z.literal("ae"),
    chunk_index: z.number().int().min(0).max(1999),
    records: z.array(aeRecord).max(MAX_RECORDS_PER_CHUNK),
    removed: z.array(z.string().regex(/^\d{1,18}$/)).max(MAX_REMOVED_PER_CHUNK).default([]),
  }),
]);

const finalizeSchema = z.object({
  sync_id: z.string().uuid(),
  stats: z.record(z.string(), z.unknown()).optional(),
});
const abortSchema = z.object({ sync_id: z.string().uuid(), reason: z.string().max(1000).optional() });
const reopenSchema = z.object({ sync_id: z.string().uuid() });
const cleanupSchema = z.object({
  sync_id: z.string().uuid(),
  max_rows: z.number().int().min(1).max(50000).default(20000),
});

const codeTableNames = [
  "naringsgrenkoder", "kommunkoder", "lankoder", "ftgstatkoder", "anstklkoder", "arbgivstatkoder",
  "aetypkoder", "jurformkoder", "omsklkoder", "agarkontrollkoder", "momsstatkoder", "fskattstatkoder",
  "bolstatkoder", "privpublkoder", "sektorkoder", "aestatkoder", "hjverksjekoder",
] as const;

const codesSchema = z.object({
  tables: z
    .array(
      z.object({
        table: z.enum(codeTableNames),
        rows: z
          .array(
            z
              .object({
                kod: z.string().min(1).max(50),
                klartext: z.string().max(500).nullable(),
                extra: z.record(z.string(), z.string().max(500).nullable()).optional(),
              })
              .strict(),
          )
          .min(1)
          .max(10000),
      }),
    )
    .min(1)
    .max(17),
});

const checkSchema = z.object({
  status: z.enum(["no_change", "count_only", "failed"]),
  source_date: z.string().max(50).nullable().optional(),
  error_message: z.string().max(1000).nullable().optional(),
  details: z.record(z.string(), z.unknown()).optional(),
});

type PgError = { code?: string; message: string };

function statusForPgError(error: PgError): number {
  switch (error.code) {
    case "57014":
    case "55P03":
    case "40P01":
    case "40001":
      return 503;
    case "02000":
      return 404;
    case "23505":
    case "22023":
      return 409;
    default:
      return 422;
  }
}

async function guard(request: Request, method: string, rate: () => boolean): Promise<Response | null> {
  if (request.method !== method) return json({ error: "Method not allowed" }, 405);
  const denied = await authorize(request);
  if (denied) return denied;
  if (rate()) return json({ error: "Too many requests" }, 429);
  return null;
}

async function readBody<T>(
  request: Request,
  schema: z.ZodType<T>,
): Promise<{ ok: true; data: T; raw: string } | { ok: false; response: Response }> {
  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) return { ok: false, response: json({ error: "Payload too large" }, 413) };
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return { ok: false, response: json({ error: "Invalid JSON" }, 400) };
  }
  const parsed = schema.safeParse(value);
  if (!parsed.success) {
    return {
      ok: false,
      response: json(
        {
          error: "Invalid payload",
          issues: parsed.error.issues.slice(0, 20).map((i) => ({ path: i.path, message: i.message })),
        },
        400,
      ),
    };
  }
  return { ok: true, data: parsed.data, raw };
}

async function admin() {
  return (await import("@/integrations/supabase/client.server")).supabaseAdmin;
}

function rpcError(label: string, error: PgError): Response {
  console.error(`[afr] ${label}:`, error.message);
  return json({ error: `${label} failed`, message: error.message, code: error.code }, statusForPgError(error));
}

/** POST /api/public/jobs/afr/start */
export async function handleAfrStart(request: Request): Promise<Response> {
  const denied = await guard(request, "POST", controlRate);
  if (denied) return denied;
  const body = await readBody(request, startSchema);
  if (!body.ok) return body.response;
  const p = body.data;
  const db = await admin();
  const { data, error } = await db.rpc("afr_start_sync", {
    p_mode: p.mode,
    p_source_date: p.source_date,
    p_api_version: p.api_version ?? "",
    p_fetched_at: p.fetched_at,
    p_je_source_count: p.je_source_count,
    p_ae_source_count: p.ae_source_count,
    p_expected_je_chunks: p.expected_je_chunks,
    p_expected_ae_chunks: p.expected_ae_chunks,
    p_confirm_large_removal: p.confirm_large_removal ?? false,
    p_details: (p.details ?? {}) as Json,
  });
  if (error) return rpcError("Start", error);
  return json({ sync_id: data, mode: p.mode }, 200);
}

/** POST /api/public/jobs/afr/chunk */
export async function handleAfrChunk(request: Request): Promise<Response> {
  const denied = await guard(request, "POST", chunkRate);
  if (denied) return denied;
  const body = await readBody(request, chunkSchema);
  if (!body.ok) return body.response;
  const p = body.data;
  const { createHash } = await import("node:crypto");
  const checksum = createHash("sha256")
    .update(JSON.stringify({ records: p.records, removed: p.removed }), "utf8")
    .digest("hex");
  const db = await admin();
  const started = performance.now();
  const { data, error } = await db.rpc("afr_store_chunk", {
    p_sync_id: p.sync_id,
    p_entity: p.entity,
    p_chunk_index: p.chunk_index,
    p_records: p.records as unknown as Json,
    p_removed: p.removed as unknown as Json,
    p_checksum: checksum,
  });
  const rpcMs = Math.round(performance.now() - started);
  if (error) return rpcError("Chunk", error);
  return json({ ...(data as Record<string, unknown>), rpc_ms: rpcMs }, 200);
}

/** POST /api/public/jobs/afr/finalize */
export async function handleAfrFinalize(request: Request): Promise<Response> {
  const denied = await guard(request, "POST", controlRate);
  if (denied) return denied;
  const body = await readBody(request, finalizeSchema);
  if (!body.ok) return body.response;
  const db = await admin();
  const { data, error } = await db.rpc("afr_finalize_sync", {
    p_sync_id: body.data.sync_id,
    p_stats: (body.data.stats ?? {}) as Json,
  });
  if (error) {
    // Transaktionen rullas tillbaka – publicerade AFR-data är oförändrade.
    await db
      .from("afr_syncs")
      .update({ error_message: error.message, last_activity_at: new Date().toISOString() })
      .eq("id", body.data.sync_id);
    return rpcError("Finalize", error);
  }
  return json({ status: "succeeded", ...(data as Record<string, unknown>) }, 200);
}

/** POST /api/public/jobs/afr/abort */
export async function handleAfrAbort(request: Request): Promise<Response> {
  const denied = await guard(request, "POST", controlRate);
  if (denied) return denied;
  const body = await readBody(request, abortSchema);
  if (!body.ok) return body.response;
  const db = await admin();
  const { data, error } = await db.rpc("afr_abort_sync", {
    p_sync_id: body.data.sync_id,
    ...(body.data.reason ? { p_reason: body.data.reason } : {}),
  });
  if (error) return rpcError("Abort", error);
  return json(data, 200);
}

/** GET: senaste ofullbordade första laddning. POST: återöppna den. */
export async function handleAfrResume(request: Request): Promise<Response> {
  const denied = await authorize(request);
  if (denied) return denied;
  if (controlRate()) return json({ error: "Too many requests" }, 429);
  const db = await admin();

  if (request.method === "GET") {
    const { data, error } = await db
      .from("afr_syncs")
      .select(
        "id, status, source_date, je_source_count, ae_source_count, expected_je_chunks, expected_ae_chunks, received_je_chunks, received_ae_chunks, stats, created_at",
      )
      .eq("mode", "initial")
      .in("status", ["failed", "receiving"])
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (error) return json({ error: "Lookup failed" }, 500);
    return json(data ?? null, 200);
  }

  if (request.method === "POST") {
    const body = await readBody(request, reopenSchema);
    if (!body.ok) return body.response;
    const { data, error } = await db.rpc("afr_reopen_initial_sync", { p_sync_id: body.data.sync_id });
    if (error) return rpcError("Resume", error);
    return json(data, 200);
  }
  return json({ error: "Method not allowed" }, 405);
}

/** POST /api/public/jobs/afr/cleanup – städar misslyckad första laddning stegvis. */
export async function handleAfrCleanup(request: Request): Promise<Response> {
  const denied = await guard(request, "POST", chunkRate);
  if (denied) return denied;
  const body = await readBody(request, cleanupSchema);
  if (!body.ok) return body.response;
  const db = await admin();
  const { data, error } = await db.rpc("afr_cleanup_failed_initial", {
    p_sync_id: body.data.sync_id,
    p_max_rows: body.data.max_rows ?? 20000,
  });
  if (error) return rpcError("Cleanup", error);
  return json(data, 200);
}

/**
 * GET /api/public/jobs/afr/hashes?entity=je|ae&after=<key>&limit=50000
 * Nuvarande id + hash, paginerat. Endast för ETL (nyckelskyddat); svaret
 * komprimeras med gzip av hostinglagret när klienten begär det.
 */
export async function handleAfrHashes(request: Request): Promise<Response> {
  const denied = await guard(request, "GET", readRate);
  if (denied) return denied;
  const url = new URL(request.url);
  const parsed = z
    .object({
      entity: z.enum(["je", "ae"]),
      after: z.string().max(40).optional(),
      limit: z.coerce.number().int().min(1).max(100000).default(50000),
    })
    .safeParse({
      entity: url.searchParams.get("entity"),
      after: url.searchParams.get("after") ?? undefined,
      limit: url.searchParams.get("limit") ?? undefined,
    });
  if (!parsed.success) return json({ error: "Invalid query" }, 400);
  const db = await admin();
  const { data, error } = await db.rpc("afr_current_hashes", {
    p_entity: parsed.data.entity,
    p_limit: parsed.data.limit,
    ...(parsed.data.after ? { p_after: parsed.data.after } : {}),
  });
  if (error) return rpcError("Hashes", error);
  return new Response(JSON.stringify(data), {
    status: 200,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

/** POST /api/public/jobs/afr/codes – synkar kodtabeller och returnerar ändringar. */
export async function handleAfrCodes(request: Request): Promise<Response> {
  const denied = await guard(request, "POST", controlRate);
  if (denied) return denied;
  const body = await readBody(request, codesSchema);
  if (!body.ok) return body.response;
  const db = await admin();
  const results: unknown[] = [];
  for (const t of body.data.tables) {
    const { data, error } = await db.rpc("afr_sync_code_table", {
      p_table: t.table,
      p_rows: t.rows as unknown as Json,
    });
    if (error) return rpcError(`Code table ${t.table}`, error);
    results.push(data);
  }
  return json({ tables: results }, 200);
}

/** POST /api/public/jobs/afr/check – loggar kontroll utan publicering (no_change, count-only, fel). */
export async function handleAfrCheck(request: Request): Promise<Response> {
  const denied = await guard(request, "POST", controlRate);
  if (denied) return denied;
  const body = await readBody(request, checkSchema);
  if (!body.ok) return body.response;
  const p = body.data;
  const db = await admin();
  const now = new Date().toISOString();
  const details = { ...(p.details ?? {}), mode: p.status } as Json;

  const { error: runError } = await db.from("data_source_runs").insert({
    source: SOURCE_ID,
    source_id: SOURCE_ID,
    status: p.status === "failed" ? "failed" : p.status === "no_change" ? "no_change" : "succeeded",
    started_at: now,
    finished_at: now,
    source_period: p.source_date ?? null,
    error_message: p.error_message ?? null,
    details,
  });
  if (runError) {
    console.error("[afr] kunde inte logga kontroll:", runError.message);
    return json({ error: "Log failed" }, 500);
  }

  const { data: existing } = await db
    .from("data_source_state")
    .select("details")
    .eq("source_id", SOURCE_ID)
    .maybeSingle();
  const merged = {
    ...((existing?.details as Record<string, unknown> | null) ?? {}),
    last_check: details,
  } as Json;

  const { error: stateError } = await db.from("data_source_state").upsert(
    {
      source_id: SOURCE_ID,
      last_checked_at: now,
      ...(p.source_date ? { latest_available_period: p.source_date } : {}),
      ...(p.status === "failed"
        ? { last_status: "failed", last_error: p.error_message ?? "Okänt fel" }
        : p.status === "no_change"
          ? { last_status: "no_change", last_error: null }
          : {}),
      details: merged,
      updated_at: now,
    },
    { onConflict: "source_id" },
  );
  if (stateError) {
    console.error("[afr] kunde inte uppdatera källstatus:", stateError.message);
    return json({ error: "State update failed" }, 500);
  }
  return json({ ok: true }, 200);
}
