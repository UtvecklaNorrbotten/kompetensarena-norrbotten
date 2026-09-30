import { z } from "zod";
import { authorize, createRateLimiter, json } from "./etl-auth.server";
import type { Json } from "@/integrations/supabase/types";

const rate = createRateLimiter(60);

const targetSchema = z.enum(["sok", "tid", "svag", "yrke", "bas"]);
const fingerprintSchema = z.object({
  period: z.string().min(1).max(20),
  checksum: z.string().min(1).max(128),
  row_count: z.number().int().min(0),
});
const upsertSchema = z.object({
  target: targetSchema,
  source_release_period: z.string().min(1).max(20).optional(),
  source_manifest: z.record(z.string(), z.unknown()).optional(),
  fingerprints: z.array(fingerprintSchema).min(1).max(1000),
});

async function readJson(request: Request) {
  try {
    return await request.json();
  } catch {
    return null;
  }
}

export async function handleAfRevisions(request: Request): Promise<Response> {
  const denied = await authorize(request);
  if (denied) return denied;
  if (rate()) return json({ error: "Too many requests" }, 429);

  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

  if (request.method === "GET") {
    const targetRaw = new URL(request.url).searchParams.get("target");
    const parsed = targetSchema.safeParse(targetRaw);
    if (!parsed.success) return json({ error: "Ogiltig target" }, 400);

    const { data, error } = await supabaseAdmin
      .from("af_revision_fingerprints")
      .select("target, period, checksum, row_count, source_release_period, source_manifest, checked_at")
      .eq("target", parsed.data)
      .order("period");

    if (error) {
      console.error("[af-revisions] läsning misslyckades:", error.message);
      return json({ error: "Lookup failed" }, 500);
    }

    return json(data ?? [], 200);
  }

  if (request.method === "POST") {
    const parsed = upsertSchema.safeParse(await readJson(request));
    if (!parsed.success) {
      return json(
        {
          error: "Invalid payload",
          issues: parsed.error.issues.map((i) => ({ path: i.path, message: i.message })),
        },
        400,
      );
    }

    const now = new Date().toISOString();
    const rows = parsed.data.fingerprints.map((fp) => ({
      target: parsed.data.target,
      period: fp.period,
      checksum: fp.checksum,
      row_count: fp.row_count,
      source_release_period: parsed.data.source_release_period ?? null,
      source_manifest: (parsed.data.source_manifest ?? {}) as Json,
      checked_at: now,
    }));

    const { error } = await supabaseAdmin
      .from("af_revision_fingerprints")
      .upsert(rows, { onConflict: "target,period" });

    if (error) {
      console.error("[af-revisions] upsert misslyckades:", error.message);
      return json({ error: "Upsert failed", message: error.message }, 422);
    }

    return json({ target: parsed.data.target, periods: rows.length, checked_at: now }, 200);
  }

  return json({ error: "Method not allowed" }, 405);
}
