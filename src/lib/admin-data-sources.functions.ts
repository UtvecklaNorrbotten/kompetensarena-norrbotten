import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import type { Database, Json } from "@/integrations/supabase/types";

/**
 * Read-only översikt över datakällor och ETL-körningar för adminvyn.
 *
 * Behörighet: kräver inloggad användare med rollen `admin` i `user_roles`
 * (kontrolleras via has_role med användarens egen session). Tabellerna
 * data_sources/data_source_state/data_source_runs är dessutom RLS-skyddade för
 * admin. Endast stagingtabellen etl_batches saknar läspolicy och läses därför
 * med serverklienten — först efter att adminrollen verifierats.
 *
 * Helt generell: inga källspecifika villkor. Nya källor i data_sources visas
 * automatiskt.
 */

type RunStatus = Database["public"]["Enums"]["run_status"];
export type SourceStatus = "ok" | "running" | "error" | "never";

export type RunView = {
  id: string;
  status: RunStatus;
  startedAt: string;
  finishedAt: string | null;
  indicatorId: string | null;
  sourcePeriod: string | null;
  rowsAffected: number | null;
  errorMessage: string | null;
  details: Json | null;
  batch: {
    id: string;
    status: Database["public"]["Enums"]["etl_batch_status"];
    receivedRows: number;
    receivedChunks: number;
    expectedChunks: number;
    isActive: boolean;
  } | null;
};

export type SourceView = {
  id: string;
  name: string;
  provider: string;
  cadence: string | null;
  sourceUrl: string | null;
  active: boolean;
  status: SourceStatus;
  stateStatus: string | null;
  lastCheckedAt: string | null;
  lastSuccessfulAt: string | null;
  latestAvailablePeriod: string | null;
  latestSuccessfulPeriod: string | null;
  lastError: string | null;
  stateDetails: Json | null;
  latestRun: RunView | null;
  latestSuccessfulRun: RunView | null;
  runs: RunView[];
};

/** Status härleds ur senaste körning; saknas körning används data_source_state. */
function deriveStatus(latest: RunView | null, stateStatus: string | null): SourceStatus {
  if (latest) {
    if (latest.status === "started") return "running";
    if (latest.status === "failed") return "error";
    return "ok";
  }
  switch (stateStatus) {
    case null:
    case "never":
      return "never";
    case "failed":
    case "error":
      return "error";
    case "started":
    case "running":
      return "running";
    default:
      return "ok";
  }
}

export const getDataSourcesOverview = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) =>
    z
      .object({
        sourceId: z.string().min(1).max(100).optional(),
        runsPerSource: z.number().int().min(1).max(100).default(5),
      })
      .parse(input ?? {}),
  )
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context;

    const { data: isAdmin, error: roleError } = await supabase.rpc("has_role", {
      _user_id: userId,
      _role: "admin",
    });
    if (roleError) throw new Error("Kunde inte kontrollera behörighet.");
    if (!isAdmin) throw new Error("FORBIDDEN");

    let sourcesQuery = supabase.from("data_sources").select("*").order("provider").order("name");
    if (data.sourceId) sourcesQuery = sourcesQuery.eq("id", data.sourceId);
    const { data: sources, error: sErr } = await sourcesQuery;
    if (sErr) throw new Error(sErr.message);
    const ids = (sources ?? []).map((s) => s.id);
    if (ids.length === 0) return [] as SourceView[];

    const [{ data: states, error: stErr }, { data: runs, error: rErr }] = await Promise.all([
      supabase.from("data_source_state").select("*").in("source_id", ids),
      supabase
        .from("data_source_runs")
        .select(
          "id, source_id, status, started_at, finished_at, indicator_id, source_period, rows_affected, error_message, details",
        )
        .in("source_id", ids)
        .order("started_at", { ascending: false })
        .limit(data.sourceId ? 200 : 1000),
    ]);
    if (stErr) throw new Error(stErr.message);
    if (rErr) throw new Error(rErr.message);

    const runIds = (runs ?? []).map((r) => r.id);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const [{ data: batches, error: bErr }, { data: active, error: aErr }] = await Promise.all([
      runIds.length
        ? supabaseAdmin
            .from("etl_batches")
            .select("id, run_id, status, received_rows, received_chunks, expected_chunks")
            .in("run_id", runIds)
        : Promise.resolve({ data: [], error: null }),
      supabaseAdmin.from("indicator_active_batches").select("active_batch_id"),
    ]);
    if (bErr) throw new Error(bErr.message);
    if (aErr) throw new Error(aErr.message);

    const activeIds = new Set((active ?? []).map((a) => a.active_batch_id));
    const batchByRun = new Map((batches ?? []).map((b) => [b.run_id, b]));
    const stateById = new Map((states ?? []).map((s) => [s.source_id, s]));

    return (sources ?? []).map((s): SourceView => {
      const all: RunView[] = (runs ?? [])
        .filter((r) => r.source_id === s.id)
        .map((r) => {
          const b = batchByRun.get(r.id);
          return {
            id: r.id,
            status: r.status,
            startedAt: r.started_at,
            finishedAt: r.finished_at,
            indicatorId: r.indicator_id,
            sourcePeriod: r.source_period,
            rowsAffected: r.rows_affected,
            errorMessage: r.error_message,
            details: r.details,
            batch: b
              ? {
                  id: b.id,
                  status: b.status,
                  receivedRows: b.received_rows,
                  receivedChunks: b.received_chunks,
                  expectedChunks: b.expected_chunks,
                  isActive: activeIds.has(b.id),
                }
              : null,
          };
        });
      const st = stateById.get(s.id);
      const latestRun = all[0] ?? null;
      return {
        id: s.id,
        name: s.name,
        provider: s.provider,
        cadence: s.cadence,
        sourceUrl: s.source_url,
        active: s.active,
        status: deriveStatus(latestRun, st?.last_status ?? null),
        stateStatus: st?.last_status ?? null,
        lastCheckedAt: st?.last_checked_at ?? null,
        lastSuccessfulAt: st?.last_successful_at ?? null,
        latestAvailablePeriod: st?.latest_available_period ?? null,
        latestSuccessfulPeriod: st?.latest_successful_period ?? null,
        lastError: st?.last_error ?? null,
        stateDetails: st?.details ?? null,
        latestRun,
        latestSuccessfulRun: all.find((r) => r.status === "succeeded") ?? null,
        runs: all.slice(0, data.runsPerSource),
      };
    });
  });
