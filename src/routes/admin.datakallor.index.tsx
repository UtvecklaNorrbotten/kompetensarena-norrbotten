import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { Section } from "@/components/layout/Section";
import { PageHeader } from "@/components/ui/PageHeader";
import { getDataSourcesOverview } from "@/lib/admin-data-sources.functions";
import {
  Notice,
  RequireSession,
  StatusBadge,
  errorText,
  fmtDate,
  fmtNum,
  runRows,
} from "@/components/admin/DataSourceParts";

export const Route = createFileRoute("/admin/datakallor/")({
  ssr: false,
  head: () => ({
    meta: [
      { title: "Datakällor (admin) – Kompetensarena Norrbotten" },
      { name: "description", content: "Intern översikt över datakällor och importstatus." },
      { property: "og:title", content: "Datakällor (admin) – Kompetensarena Norrbotten" },
      { property: "og:description", content: "Intern översikt över datakällor och importstatus." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
      { name: "robots", content: "noindex, nofollow" },
    ],
  }),
  component: Page,
});

function Page() {
  return (
    <>
      <Section tone="light" className="py-10 md:py-12">
        <PageHeader
          eyebrow="Admin"
          title="Datakällor"
          intro="Status för varje registrerad datakälla och dess senaste importer. Sidan är skrivskyddad."
        />
      </Section>
      <Section className="py-8 md:py-10">
        <RequireSession>
          <Overview />
        </RequireSession>
      </Section>
    </>
  );
}

function Overview() {
  const fetchOverview = useServerFn(getDataSourcesOverview);
  const q = useQuery({
    queryKey: ["admin", "data-sources"],
    queryFn: () => fetchOverview({ data: { runsPerSource: 1 } }),
  });
  if (q.isPending) return <p className="text-ink-muted">Hämtar…</p>;
  if (q.isError) return <Notice title="Fel">{errorText(q.error)}</Notice>;
  if (q.data.length === 0) return <Notice title="Inga datakällor">Inga datakällor är registrerade.</Notice>;

  return (
    <div className="overflow-x-auto rounded-md border border-border">
      <table className="w-full min-w-[960px] text-sm">
        <thead className="bg-neutral-surface text-left">
          <tr>
            {["Datakälla", "Status", "Senaste lyckade import", "Senaste körning", "Period", "Observationer", "Aktiv batch", "Senaste fel"].map((h) => (
              <th key={h} scope="col" className="px-3 py-2 font-semibold">{h}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {q.data.map((s) => {
            const ok = s.latestSuccessfulRun;
            const failed = s.latestRun?.status === "failed";
            return (
              <tr key={s.id} className="border-t border-border align-top">
                <td className="px-3 py-2">
                  <Link
                    to="/admin/datakallor/$sourceId"
                    params={{ sourceId: s.id }}
                    className="font-semibold text-brand-dark underline-offset-2 hover:underline"
                  >
                    {s.name}
                  </Link>
                  <div className="font-mono text-xs text-ink-muted">{s.id}</div>
                  <div className="text-xs text-ink-muted">{s.provider}{s.active ? "" : " · inaktiv"}</div>
                </td>
                <td className="px-3 py-2"><StatusBadge status={s.status} /></td>
                <td className="px-3 py-2">{fmtDate(ok?.finishedAt ?? s.lastSuccessfulAt)}</td>
                <td className="px-3 py-2">{fmtDate(s.latestRun?.startedAt ?? s.lastCheckedAt)}</td>
                <td className="px-3 py-2">{s.latestSuccessfulPeriod ?? ok?.sourcePeriod ?? "–"}</td>
                <td className="px-3 py-2 tabular-nums">{fmtNum(runRows(ok))}</td>
                <td className="px-3 py-2 font-mono text-xs">
                  {ok?.batch ? `${ok.batch.id.slice(0, 8)}${ok.batch.isActive ? " (aktiv)" : ""}` : "–"}
                </td>
                <td className="max-w-xs px-3 py-2 text-xs text-destructive">
                  {failed ? (s.latestRun?.errorMessage ?? s.lastError ?? "Okänt fel") : s.status === "error" ? (s.lastError ?? "–") : "–"}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
