import { useState } from "react";
import {
  CartesianGrid,
  ErrorBar,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { countAxis } from "@/lib/education-axis";
import { demandNumber, demandValue, type DemandRank } from "@/lib/labour-demand";
import type { AfValue } from "@/lib/af-unemployment";

export type DemandChartRow = {
  period: string;
  value: AfValue;
  comparison?: AfValue | undefined;
  margin?: number | null;
};
export function DemandTimeChart({
  rows,
  name,
  comparisonName = "Riket",
  unit = "platser",
}: {
  rows: DemandChartRow[];
  name: string;
  comparisonName?: string;
  unit?: string;
}) {
  const [compare, setCompare] = useState(false);
  const [table, setTable] = useState(false);
  const axis = countAxis(
    rows
      .flatMap((r) => [
        demandValue(r.value),
        compare ? demandValue(r.comparison) : null,
        typeof r.value === "number" && typeof r.margin === "number" ? r.value + r.margin : null,
      ])
      .filter((v): v is number => v !== null),
  );
  const chart = rows.map((r) => ({
    ...r,
    plot: demandValue(r.value),
    other: demandValue(r.comparison),
  }));
  const hasValues = chart.some((r) => r.plot !== null);
  const hasMargins = rows.some((r) => r.margin != null);
  const download = () => {
    const escape = (v: unknown) => `"${String(v).replaceAll('"', '""')}"`;
    const csv = [
      ["Period", name, comparisonName, "Osäkerhetsmarginal", "Enhet"],
      ...rows.map((r) => [
        r.period,
        demandNumber(r.value, 1),
        demandNumber(r.comparison, 1),
        demandNumber(r.margin, 1),
        unit,
      ]),
    ]
      .map((r) => r.map(escape).join(";"))
      .join("\r\n");
    const url = URL.createObjectURL(new Blob(["\uFEFF" + csv], { type: "text/csv;charset=utf-8" }));
    const a = document.createElement("a");
    a.href = url;
    a.download = "efterfragan-pa-arbetskraft.csv";
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };
  return (
    <>
      {hasValues ? (
        <div
          className="h-80 min-w-0"
          role="img"
          aria-label={`${name}, ${unit}. Exakta värden finns i datatabellen.`}
        >
          <ResponsiveContainer width="100%" height="100%">
            <LineChart
              data={chart}
              margin={{ top: 20, right: 15, left: 0, bottom: 8 }}
              accessibilityLayer
            >
              <CartesianGrid vertical={false} stroke="var(--border)" strokeDasharray="3 3" />
              <XAxis dataKey="period" minTickGap={45} tick={{ fontSize: 12 }} />
              <YAxis
                domain={[0, axis.maximum]}
                ticks={axis.ticks.filter((v) => v >= 0)}
                width={72}
                tickFormatter={(v) => demandNumber(v, 1)}
                tick={{ fontSize: 12 }}
              />
              <Tooltip
                formatter={(v: number, label: string) => [`${demandNumber(v, 1)} ${unit}`, label]}
                contentStyle={{ borderRadius: 8, borderColor: "var(--border)" }}
              />
              <Line
                dataKey="plot"
                name={name}
                stroke="var(--chart-1)"
                strokeWidth={2.5}
                dot={hasMargins}
                connectNulls={false}
                isAnimationActive={false}
              >
                {hasMargins && <ErrorBar dataKey="margin" width={5} stroke="var(--ink)" />}
              </Line>
              <Line
                hide={!compare}
                dataKey="other"
                name={comparisonName}
                stroke="var(--chart-3)"
                strokeWidth={2.5}
                dot={false}
                connectNulls={false}
                isAnimationActive={false}
              />
            </LineChart>
          </ResponsiveContainer>
        </div>
      ) : (
        <p className="py-12 text-ink-muted">Uppgifter saknas för urvalet.</p>
      )}
      <div className="mt-4 flex flex-wrap justify-center gap-5 text-sm">
        <span className="inline-flex items-center gap-2">
          <span className="h-1 w-5 bg-[var(--chart-1)]" />
          {name}
        </span>
        {rows.some((r) => typeof r.comparison === "number") && (
          <button
            type="button"
            className="underline underline-offset-4"
            aria-pressed={compare}
            onClick={() => setCompare(!compare)}
          >
            {compare ? "Dölj" : "Visa"} {comparisonName}
          </button>
        )}
      </div>
      <div className="mt-5 flex justify-center gap-6 border-t border-border pt-4 text-sm text-brand-dark">
        <button
          type="button"
          className="underline underline-offset-4"
          aria-expanded={table}
          onClick={() => setTable(!table)}
        >
          {table ? "Dölj" : "Visa"} datatabell
        </button>
        <button type="button" className="underline underline-offset-4" onClick={download}>
          Ladda ned CSV
        </button>
      </div>
      {table && (
        <div className="mt-4 max-h-80 overflow-auto">
          <table className="w-full text-sm">
            <caption className="sr-only">
              {name}, {unit}
            </caption>
            <thead>
              <tr>
                <th className="p-2 text-left" scope="col">
                  Period
                </th>
                <th scope="col">{name}</th>
                {rows.some((r) => r.comparison !== undefined) && (
                  <th scope="col">{comparisonName}</th>
                )}
                {hasMargins && <th scope="col">Osäkerhetsmarginal ±</th>}
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.period} className="border-t border-border">
                  <th scope="row" className="p-2 text-left font-normal">
                    {r.period}
                  </th>
                  <td className="text-center">{demandNumber(r.value, 1)}</td>
                  {rows.some((r) => r.comparison !== undefined) && (
                    <td className="text-center">{demandNumber(r.comparison, 1)}</td>
                  )}
                  {hasMargins && <td className="text-center">{demandNumber(r.margin)}</td>}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}

export function DemandRanking({
  rows,
  onSelect,
  unit = "platser",
  allowChange = true,
}: {
  rows: DemandRank[];
  onSelect?: (code: string) => void;
  unit?: string;
  allowChange?: boolean;
}) {
  const [all, setAll] = useState(false);
  const [order, setOrder] = useState("value");
  const number = (r: DemandRank) => (order === "value" ? demandValue(r.value) : r.change);
  const sorted = [...rows]
    .filter((r) => number(r) !== null)
    .sort((a, b) => (order === "decrease" ? number(a)! - number(b)! : number(b)! - number(a)!));
  const shown = all ? sorted : sorted.slice(0, 10);
  const maximum = countAxis(sorted.map((r) => Math.abs(number(r)!))).maximum;
  const missing = rows.filter((r) => number(r) === null);
  return (
    <>
      {allowChange && (
        <label className="mb-5 block text-sm">
          Rangordna efter
          <select
            className="ml-3 rounded-md border border-border bg-surface p-2"
            value={order}
            onChange={(e) => setOrder(e.target.value)}
          >
            <option value="value">Antal</option>
            <option value="increase">Störst ökning på ett år</option>
            <option value="decrease">Störst minskning på ett år</option>
          </select>
        </label>
      )}
      {order !== "value" && (
        <p className="mb-4 text-sm text-ink-muted">
          Förändring i antal jämfört med samma månad föregående år. En ökning behöver inte betyda
          större arbetskraftsbrist.
        </p>
      )}
      <div className="space-y-4" role="list" aria-label={`Rangordning, ${unit}`}>
        {shown.map((r) => (
          <div key={r.code} role="listitem">
            <div className="mb-1 flex items-baseline justify-between gap-4 text-sm">
              {onSelect ? (
                <button
                  type="button"
                  className="text-left text-brand-dark underline underline-offset-4"
                  onClick={() => onSelect(r.code)}
                >
                  {r.label}
                </button>
              ) : (
                <span>{r.label}</span>
              )}
              <span className="shrink-0 tabular-nums">
                {order !== "value" && number(r)! > 0 ? "+" : ""}
                {demandNumber(number(r))}
              </span>
            </div>
            <div className="h-3 rounded-sm bg-muted">
              <div
                className={`h-3 rounded-sm ${number(r)! < 0 ? "bg-[var(--chart-3)]" : "bg-[var(--chart-1)]"}`}
                style={{ width: `${(Math.abs(number(r)!) / maximum) * 100}%` }}
              />
            </div>
          </div>
        ))}
      </div>
      {!shown.length && <p className="py-6 text-ink-muted">Inga jämförbara värden för urvalet.</p>}
      <p className="mt-4 text-xs text-ink-muted">
        Stapellängd: 0–{demandNumber(maximum)} {order !== "value" ? "i absolut förändring" : unit}.{" "}
        {missing.length > 0 ? `${missing.length} kategorier saknar jämförbara värden.` : ""}
      </p>
      {sorted.length > 10 && (
        <button
          type="button"
          className="mx-auto mt-6 block text-sm text-brand-dark underline underline-offset-4"
          aria-expanded={all}
          onClick={() => setAll(!all)}
        >
          {all ? "Visa topp 10" : `Visa alla ${sorted.length}`}
        </button>
      )}
      {missing.length > 0 && (
        <details className="mt-4 text-sm">
          <summary className="cursor-pointer text-brand-dark">
            Saknade eller skyddade uppgifter
          </summary>
          <ul className="mt-3 space-y-2">
            {missing.map((r) => (
              <li key={r.code}>
                {r.label}: {demandNumber(r.value)}
                {order !== "value" ? `; föregående år: ${demandNumber(r.previous)}` : ""}
              </li>
            ))}
          </ul>
        </details>
      )}
    </>
  );
}
