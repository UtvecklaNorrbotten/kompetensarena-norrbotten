import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  BarChart,
  Bar,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
  Legend,
} from "recharts";
import snapshot from "@/data/workforce/catalog.json";
import { getWorkforceSlice } from "@/lib/aggregates.functions";
import { workforcePoint, workforceValue, type WorkforceCatalog } from "@/lib/workforce";
import { countAxis } from "@/lib/education-axis";
import { employmentNumber } from "@/lib/employment";
const catalog = snapshot as WorkforceCatalog;
export function WorkforcePyramid({ geo }: { geo: string }) {
  const info = catalog.datasets["age-year"]!;
  const [period, setPeriod] = useState(info.periods.at(-1)!);
  const [table, setTable] = useState(false);
  const measure = Object.entries(info.measures).find(([, l]) => l.includes("(arbetskraften)"))![0];
  const query = useQuery({
    queryKey: ["workforce", "age-year", geo],
    queryFn: () => getWorkforceSlice({ data: { dataset: "age-year", geo } }),
    staleTime: 3600000,
  });
  // A disjoint partition: omit 16–19 and all overlapping broad age intervals.
  const ages = [
    "15-19",
    "20-24",
    "25-29",
    "30-34",
    "35-39",
    "40-44",
    "45-49",
    "50-54",
    "55-59",
    "060-64",
    "65-69",
    "70-74",
  ];
  const rows = [...ages].reverse().map((age) => {
    const men = workforceValue(workforcePoint(query.data ?? [], period, "1", age, age, measure));
    const women = workforceValue(workforcePoint(query.data ?? [], period, "2", age, age, measure));
    return { label: info.ages[age]!, men: men == null ? null : -men, women };
  });
  const axis = countAxis(rows.flatMap((r) => [r.men == null ? 0 : -r.men, r.women ?? 0]));
  const download = () => {
    const data = [
      ["Geografi", "År", "Ålder", "Män", "Kvinnor", "Enhet", "Källa"],
      ...rows.map((r) => [
        catalog.geographies[geo],
        period,
        r.label,
        r.men == null ? "Uppgift saknas" : -r.men,
        r.women ?? "Uppgift saknas",
        "personer",
        `SCB ${info.table}, årsmedelvärde, ${info.updated}`,
      ]),
    ]
      .map((r) => r.map((v) => `"${String(v).replaceAll('"', '""')}"`).join(";"))
      .join("\r\n");
    const url = URL.createObjectURL(
      new Blob(["\uFEFF" + data], { type: "text/csv;charset=utf-8" }),
    );
    const a = document.createElement("a");
    a.href = url;
    a.download = "arbetskraft-alder.csv";
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };
  return (
    <section
      id="alder"
      className="min-w-0 scroll-mt-28 rounded-xl border border-border bg-surface p-5 md:p-8"
    >
      <h2 className="text-2xl md:text-3xl">Hur gammal är arbetskraften?</h2>
      <p className="mb-6 mt-3 text-ink-muted">
        {catalog.geographies[geo]} · Arbetskraften 15–74 år. Årsmedelvärde med kvinnor och män i
        åldersgrupper som inte överlappar.
      </p>
      <label className="mb-6 block text-sm font-semibold">
        Åldersstrukturens referensår
        <select
          className="ml-3 rounded border border-border bg-surface p-2"
          value={period}
          onChange={(e) => setPeriod(e.target.value)}
        >
          {[...info.periods].reverse().map((p) => (
            <option key={p}>{p}</option>
          ))}
        </select>
      </label>
      {query.isPending ? (
        <p role="status">Hämtar åldersstruktur…</p>
      ) : query.isError ? (
        <p role="alert">
          Åldersuppgifterna kunde inte läsas.{" "}
          <button className="underline" onClick={() => void query.refetch()}>
            Försök igen
          </button>
        </p>
      ) : (
        <>
          <div
            role="img"
            aria-label="Arbetskraftens ålderspyramid. Män till vänster och kvinnor till höger. Exakta värden finns i datatabellen."
            className="h-[480px] w-full min-w-0"
          >
            <ResponsiveContainer width="100%" height="100%">
              <BarChart
                layout="vertical"
                data={rows}
                stackOffset="sign"
                margin={{ left: 0, right: 12, top: 10, bottom: 10 }}
                accessibilityLayer
              >
                <CartesianGrid horizontal={false} stroke="var(--border)" />
                <XAxis
                  type="number"
                  domain={[-axis.maximum, axis.maximum]}
                  ticks={[
                    ...axis.ticks
                      .filter((v) => v > 0)
                      .map((v) => -v)
                      .reverse(),
                    ...axis.ticks,
                  ]}
                  tickFormatter={(v) => employmentNumber(Math.abs(v))}
                />
                <YAxis type="category" dataKey="label" width={77} tick={{ fontSize: 12 }} />
                <Tooltip
                  wrapperStyle={{ maxWidth: "80vw" }}
                  formatter={(v: number, label: string) => [
                    employmentNumber(Math.abs(v)) + " personer",
                    label,
                  ]}
                />
                <Legend />
                <Bar
                  dataKey="men"
                  name="Män"
                  stackId="age"
                  fill="var(--chart-3)"
                  isAnimationActive={false}
                />
                <Bar
                  dataKey="women"
                  name="Kvinnor"
                  stackId="age"
                  fill="var(--chart-1)"
                  isAnimationActive={false}
                />
              </BarChart>
            </ResponsiveContainer>
          </div>
          <div className="mt-5 flex justify-center gap-5 text-sm">
            <button className="underline" aria-expanded={table} onClick={() => setTable(!table)}>
              {table ? "Dölj" : "Visa"} datatabell
            </button>
            <button className="underline" onClick={download}>
              Ladda ned CSV
            </button>
          </div>
          {table && (
            <div className="mt-5 overflow-auto">
              <table className="w-full text-sm">
                <caption className="pb-3 text-left">
                  {catalog.geographies[geo]} · {period} · personer
                </caption>
                <thead>
                  <tr>
                    <th className="p-2 text-left">Ålder</th>
                    <th className="p-2 text-right">Män</th>
                    <th className="p-2 text-right">Kvinnor</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.label} className="border-t border-border">
                      <th className="p-2 text-left font-normal">{r.label}</th>
                      <td className="p-2 text-right">
                        {employmentNumber(r.men == null ? null : -r.men)}
                      </td>
                      <td className="p-2 text-right">{employmentNumber(r.women)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
      <p className="mt-6 border-t border-border pt-4 text-sm text-ink-muted">
        Källa: SCB, {info.table}. BAS preliminär statistik, årsmedelvärde {period}. Källa uppdaterad{" "}
        {info.updated.slice(0, 10)}.
      </p>
    </section>
  );
}
