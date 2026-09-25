import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { Section } from "@/components/layout/Section";
import { getDataSourcesOverview, type SourceView } from "@/lib/admin-data-sources.functions";
import {
  Notice,
  RequireSession,
  RunStatusBadge,
  StatusBadge,
  errorText,
  fmtDate,
  fmtDuration,
  fmtNum,
  runRows,
} from "@/components/admin/DataSourceParts";

const RUN_LIMIT = 25;

export const Route = createFileRoute("/admin/datakallor/$sourceId")({
  ssr: false,
  head: () => ({
    meta: [
      { title: "Datakälla (admin) – Kompetensarena Norrbotten" },
      { name: "description", content: "Intern detaljvy för en datakälla och dess körningar." },
      { property: "og:title", content: "Datakälla (admin) – Kompetensarena Norrbotten" },
      { property: "og:description", content: "Intern detaljvy för en datakälla och dess körningar." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
      { name: "robots", content: "noindex, nofollow" },
    ],
  }),
  component: Page,
});

function Page() {
  const { sourceId } = Route.useParams();
  return (
    <Section className="py-8 md:py-10">
      <Link to="/admin/datakallor" className="text-sm text-brand-dark underline-offset-2 hover:underline">
        ← Alla datakällor
      </Link>
      <div className="mt-4">
        <RequireSession>
          <Detail sourceId={sourceId} />
        </RequireSession>
      </div>
    </Section>
  );
}

function Detail({ sourceId }: { sourceId: string }) {
  const fetchOverview = useServerFn(getDataSourcesOverview);
  const q = useQuery({
    queryKey: ["admin", "data-sources", sourceId],
    queryFn: () => fetchOverview({ data: { sourceId, runsPerSource: RUN_LIMIT } }),
  });
  if (q.isPending) return <p className="text-ink-muted">Hämtar…</p>;
  if (q.isError) return <Notice title="Fel">{errorText(q.error)}</Notice>;
  const s = q.data[0];
  if (!s) return <Notice title="Hittades inte">Datakällan {sourceId} finns inte.</Notice>;
  return <SourceDetail s={s} />;
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <dt className="text-xs uppercase tracking-wide text-ink-muted">{label}</dt>
      <dd className="mt-0.5 break-words">{children}</dd>
    </div>
  );
}

function SourceDetail({ s }: { s: SourceView }) {
  const ok = s.latestSuccessfulRun;
  const hasDetails = s.stateDetails && JSON.stringify(s.stateDetails) !== "{}";
  return (
    <div className="space-y-8">
      <div className="flex flex-wrap items-center gap-3">
        <h1 className="text-3xl">{s.name}</h1>
        <StatusBadge status={s.status} />
      </div>

      <dl className="grid grid-cols-1 gap-4 rounded-md border border-border bg-surface p-5 text-sm sm:grid-cols-2 lg:grid-cols-4">
        <Field label="source_key"><span className="font-mono">{s.id}</span></Field>
        <Field label="Leverantör">{s.provider}</Field>
        <Field label="Kadens">{s.cadence ?? "–"}</Field>
        <Field label="Aktiv">{s.active ? "Ja" : "Nej"}</Field>
        <Field label="Senaste lyckade import">{fmtDate(ok?.finishedAt ?? s.lastSuccessfulAt)}</Field>
        <Field label="Senast kontrollerad">{fmtDate(s.lastCheckedAt)}</Field>
        <Field label="Senaste lyckade period">{s.latestSuccessfulPeriod ?? ok?.sourcePeriod ?? "–"}</Field>
        <Field label="Senaste tillgängliga period">{s.latestAvailablePeriod ?? "–"}</Field>
        <Field label="Observationer (senaste lyckade)">{fmtNum(runRows(ok))}</Field>
        <Field label="Aktiv batch">
          <span className="font-mono text-xs">{ok?.batch ? `${ok.batch.id}${ok.batch.isActive ? " (aktiv)" : ""}` : "–"}</span>
        </Field>
        <Field label="Status i källregistret">{s.stateStatus ?? "–"}</Field>
        <Field label="Källadress">
          {s.sourceUrl ? <a href={s.sourceUrl} target="_blank" rel="noreferrer" className="text-brand-dark underline">{s.sourceUrl}</a> : "–"}
        </Field>
        {s.lastError && (
          <div className="sm:col-span-2 lg:col-span-4">
            <Field label="Senaste fel i källregistret"><span className="text-destructive">{s.lastError}</span></Field>
          </div>
        )}
      </dl>

      {hasDetails && (
        <details className="rounded-md border border-border p-4 text-sm">
          <summary className="cursor-pointer font-semibold">Teknisk metadata (källregister)</summary>
          <pre className="mt-3 max-h-96 overflow-auto whitespace-pre-wrap text-xs">{JSON.stringify(s.stateDetails, null, 2)}</pre>
        </details>
      )}

      <div>
        <h2 className="mb-3 text-xl">Senaste körningar <span className="text-sm text-ink-muted">(max {RUN_LIMIT}, senaste först)</span></h2>
        {s.runs.length === 0 ? (
          <Notice title="Inga körningar">Inga körningar är loggade för den här datakällan.</Notice>
        ) : (
          <div className="overflow-x-auto rounded-md border border-border">
            <table className="w-full min-w-[960px] text-sm">
              <thead className="bg-neutral-surface text-left">
                <tr>
                  {["Start", "Slut", "Tid", "Resultat", "Indikator", "Period", "Observationer", "Batch", "Fel / detaljer"].map((h) => (
                    <th key={h} scope="col" className="px-3 py-2 font-semibold">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {s.runs.map((r) => (
                  <tr key={r.id} className="border-t border-border align-top">
                    <td className="px-3 py-2 whitespace-nowrap">{fmtDate(r.startedAt)}</td>
                    <td className="px-3 py-2 whitespace-nowrap">{fmtDate(r.finishedAt)}</td>
                    <td className="px-3 py-2 whitespace-nowrap">{fmtDuration(r.startedAt, r.finishedAt)}</td>
                    <td className="px-3 py-2"><RunStatusBadge status={r.status} /></td>
                    <td className="px-3 py-2 font-mono text-xs">{r.indicatorId ?? "–"}</td>
                    <td className="px-3 py-2">{r.sourcePeriod ?? "–"}</td>
                    <td className="px-3 py-2 tabular-nums">{fmtNum(runRows(r))}</td>
                    <td className="px-3 py-2 font-mono text-xs">
                      {r.batch ? (
                        <>
                          {r.batch.id.slice(0, 8)} · {r.batch.status}
                          {r.batch.isActive && " · aktiv"}
                          <div className="text-ink-muted">{r.batch.receivedChunks}/{r.batch.expectedChunks} delar</div>
                        </>
                      ) : "–"}
                    </td>
                    <td className="max-w-sm px-3 py-2 text-xs">
                      {r.errorMessage && <p className="text-destructive">{r.errorMessage}</p>}
                      {r.details && JSON.stringify(r.details) !== "{}" && (
                        <details>
                          <summary className="cursor-pointer text-ink-muted">Detaljer</summary>
                          <pre className="mt-1 max-h-64 overflow-auto whitespace-pre-wrap">{JSON.stringify(r.details, null, 2)}</pre>
                        </details>
                      )}
                      {!r.errorMessage && (!r.details || JSON.stringify(r.details) === "{}") && "–"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
