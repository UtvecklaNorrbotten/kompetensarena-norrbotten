import { useEffect, useState, type ReactNode } from "react";
import { supabase } from "@/integrations/supabase/client";
import type { RunView, SourceStatus } from "@/lib/admin-data-sources.functions";
import { cn } from "@/lib/utils";

/** Presentationsdelar för adminvyn över datakällor. Inga källspecifika regler. */

const statusLabel: Record<SourceStatus, string> = {
  ok: "OK",
  running: "Körning pågår",
  error: "Fel",
  never: "Aldrig körd",
};

const statusClass: Record<SourceStatus, string> = {
  ok: "bg-brand-light text-ink border-brand",
  running: "bg-accent-orange-light text-ink border-accent-orange",
  error: "bg-destructive/10 text-destructive border-destructive",
  never: "bg-neutral-surface text-ink-muted border-border",
};

export function StatusBadge({ status }: { status: SourceStatus }) {
  return (
    <span
      className={cn(
        "inline-flex items-center whitespace-nowrap rounded-full border px-2.5 py-0.5 text-xs font-semibold",
        statusClass[status],
      )}
    >
      {statusLabel[status]}
    </span>
  );
}

const runStatusMap: Record<RunView["status"], { label: string; status: SourceStatus }> = {
  succeeded: { label: "Lyckad", status: "ok" },
  no_change: { label: "Ingen ny data", status: "ok" },
  started: { label: "Pågår / ofullständig", status: "running" },
  failed: { label: "Misslyckad", status: "error" },
};

export function RunStatusBadge({ status }: { status: RunView["status"] }) {
  const m = runStatusMap[status];
  return (
    <span
      className={cn(
        "inline-flex items-center whitespace-nowrap rounded-full border px-2 py-0.5 text-xs font-semibold",
        statusClass[m.status],
      )}
    >
      {m.label}
    </span>
  );
}

const dtf = new Intl.DateTimeFormat("sv-SE", {
  dateStyle: "short",
  timeStyle: "short",
  timeZone: "Europe/Stockholm",
});
export function fmtDate(v: string | null | undefined) {
  return v ? dtf.format(new Date(v)) : "–";
}
export function fmtNum(v: number | null | undefined) {
  return v == null ? "–" : v.toLocaleString("sv-SE");
}
export function fmtDuration(start: string, end: string | null) {
  if (!end) return "–";
  const s = Math.round((new Date(end).getTime() - new Date(start).getTime()) / 1000);
  if (s < 60) return `${s} s`;
  const m = Math.floor(s / 60);
  return m < 60 ? `${m} min ${s % 60} s` : `${Math.floor(m / 60)} h ${m % 60} min`;
}

/** Antal observationer i en körning: batchens mottagna rader, annars rows_affected. */
export function runRows(run: RunView | null) {
  if (!run) return null;
  return run.batch?.receivedRows ?? run.rowsAffected;
}

/**
 * Visar innehållet endast när en session finns. Själva behörigheten (admin)
 * avgörs på servern; här undviks bara ett onödigt anrop utan inloggning.
 */
export function RequireSession({ children }: { children: ReactNode }) {
  const [state, setState] = useState<"loading" | "in" | "out">("loading");
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setState(data.session ? "in" : "out"));
  }, []);
  if (state === "loading") return <p className="text-ink-muted">Kontrollerar inloggning…</p>;
  if (state === "out")
    return (
      <Notice title="Inloggning krävs">
        Den här sidan är endast för administratörer. Inloggning är ännu inte byggd i
        webbplatsen, så sidan kan bara visas för en inloggad användare med adminroll.
      </Notice>
    );
  return <>{children}</>;
}

export function Notice({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div role="status" className="rounded-md border border-border bg-surface p-5">
      <p className="font-semibold">{title}</p>
      <p className="mt-1 text-ink-muted">{children}</p>
    </div>
  );
}

export function errorText(err: unknown) {
  const msg = err instanceof Error ? err.message : String(err);
  if (msg.includes("FORBIDDEN")) return "Ditt konto saknar adminbehörighet.";
  if (msg.includes("Unauthorized")) return "Du behöver logga in igen.";
  return `Kunde inte hämta data: ${msg}`;
}
