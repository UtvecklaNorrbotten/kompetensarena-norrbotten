import { z } from "zod";
import { authorize, createRateLimiter, json } from "./etl-auth.server";

const stateRate = createRateLimiter(120);
const MAX_BODY_BYTES = 256_000;

const sourceIdSchema = z.string().min(1).max(100);

const updateSchema = z.object({
  source_id: sourceIdSchema,
  status: z.enum(["waiting", "ready", "no_change", "succeeded", "failed"]),
  latest_available_period: z.string().max(50).nullable().optional(),
  latest_successful_period: z.string().max(50).nullable().optional(),
  error_message: z.string().max(1000).nullable().optional(),
  details: z.record(z.string(), z.unknown()).optional(),
});

export async function handleSourceStateGet(request: Request): Promise<Response> {
  if (request.method !== "GET") return json({ error: "Method not allowed" }, 405);
  const denied = await authorize(request);
  if (denied) return denied;
  if (stateRate()) return json({ error: "Too many requests" }, 429);

  const url = new URL(request.url);
  const parsed = sourceIdSchema.safeParse(url.searchParams.get("source_id"));
  if (!parsed.success) return json({ error: "Invalid source_id" }, 400);

  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

  const { data: source, error: sourceError } = await supabaseAdmin
    .from("data_sources")
    .select("id, provider, name, source_url, cadence, expected_day_of_month, active")
    .eq("id", parsed.data)
    .maybeSingle();

  if (sourceError) {
    console.error("[source-state] källuppslag misslyckades:", sourceError.message);
    return json({ error: "Lookup failed" }, 500);
  }
  if (!source) return json({ error: "Unknown source" }, 404);

  const { data: state, error: stateError } = await supabaseAdmin
    .from("data_source_state")
    .select(
      "latest_available_period, latest_successful_period, last_checked_at, last_successful_at, last_status, last_error, details, updated_at",
    )
    .eq("source_id", parsed.data)
    .maybeSingle();

  if (stateError) {
    console.error("[source-state] statusuppslag misslyckades:", stateError.message);
    return json({ error: "Lookup failed" }, 500);
  }

  return json({ ...source, state: state ?? null }, 200);
}

export async function handleSourceStatePost(request: Request): Promise<Response> {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const denied = await authorize(request);
  if (denied) return denied;
  if (stateRate()) return json({ error: "Too many requests" }, 429);

  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) return json({ error: "Payload too large" }, 413);

  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const parsed = updateSchema.safeParse(value);
  if (!parsed.success) return json({ error: "Invalid payload" }, 400);

  const payload = parsed.data;
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

  const { data: source, error: sourceError } = await supabaseAdmin
    .from("data_sources")
    .select("id, provider")
    .eq("id", payload.source_id)
    .maybeSingle();

  if (sourceError) return json({ error: "Lookup failed" }, 500);
  if (!source) return json({ error: "Unknown source" }, 404);

  const now = new Date().toISOString();
  const stateRow: Record<string, unknown> = {
    source_id: payload.source_id,
    last_status: payload.status,
    last_checked_at: now,
    updated_at: now,
    last_error: payload.status === "failed" ? payload.error_message ?? "Okänt fel" : null,
  };

  if (payload.latest_available_period !== undefined) {
    stateRow.latest_available_period = payload.latest_available_period;
  }
  if (payload.details !== undefined) stateRow.details = payload.details;

  if (payload.status === "succeeded") {
    const successfulPeriod =
      payload.latest_successful_period ?? payload.latest_available_period ?? null;
    stateRow.latest_successful_period = successfulPeriod;
    stateRow.last_successful_at = now;
  } else if (payload.latest_successful_period !== undefined) {
    stateRow.latest_successful_period = payload.latest_successful_period;
  }

  const { data: state, error: upsertError } = await supabaseAdmin
    .from("data_source_state")
    .upsert(stateRow, { onConflict: "source_id" })
    .select(
      "source_id, latest_available_period, latest_successful_period, last_checked_at, last_successful_at, last_status, last_error, details, updated_at",
    )
    .single();

  if (upsertError) {
    console.error("[source-state] kunde inte uppdatera status:", upsertError.message);
    return json({ error: "State update failed" }, 500);
  }

  if (["no_change", "succeeded", "failed"].includes(payload.status)) {
    const runStatus = payload.status;
    const { error: runError } = await supabaseAdmin.from("data_source_runs").insert({
      source: source.provider,
      source_id: payload.source_id,
      source_period:
        payload.latest_successful_period ?? payload.latest_available_period ?? null,
      status: runStatus,
      started_at: now,
      finished_at: now,
      rows_affected: 0,
      error_message: payload.status === "failed" ? payload.error_message ?? null : null,
      details: payload.details ?? null,
    });

    if (runError) {
      console.error("[source-state] körningslogg kunde inte skrivas:", runError.message);
      return json({ error: "Run logging failed" }, 500);
    }
  }

  return json(state, 200);
}
