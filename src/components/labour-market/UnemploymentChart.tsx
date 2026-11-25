import { useState } from "react";
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { countAxis } from "@/lib/education-axis";
import { afNumber } from "@/lib/af-unemployment";
export type UnemploymentChartPoint = {
  period: string;
  selected: number | null;
  country: number | null;
  selectedSuppressed?: boolean;
  countrySuppressed?: boolean;
};
export function UnemploymentChart({
  rows,
  title,
  name,
  unit,
  comparisonName = "Riket",
}: {
  comparisonName?: string;
  rows: UnemploymentChartPoint[];
  title: string;
  name: string;
  unit: string;
}) {
  const [table, setTable] = useState(false);
  const [showComparison, setShowComparison] = useState(unit === "%" || comparisonName !== "Riket");
  const hasComparison = rows.some((r) => r.country !== null);
  const values = rows
    .flatMap((r) => [r.selected, showComparison ? r.country : null])
    .filter((v): v is number => v !== null);
  const axis = countAxis(values);
  const download = () => {
    const escape = (v: unknown) => `"${String(v ?? "Uppgift saknas").replaceAll('"', '""')}"`;
    const csv = [
      ["Månad", name, comparisonName, "Enhet"],
      ...rows.map((r) => [
        r.period,
        r.selectedSuppressed ? "Sekretess" : r.selected,
        r.countrySuppressed ? "Sekretess" : r.country,
        unit,
      ]),
    ]
      .map((r) => r.map(escape).join(";"))
      .join("\r\n");
    const url = URL.createObjectURL(new Blob(["\uFEFF" + csv], { type: "text/csv;charset=utf-8" }));
    const a = document.createElement("a");
    a.href = url;
    a.download = "arbetsloshet.csv";
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };
  return (
    <>
      {!values.length ? (
        <p className="py-12 text-ink-muted">Det finns inga jämförbara uppgifter för urvalet.</p>
      ) : (
        <div
          className="h-80 w-full min-w-0"
          role="img"
          aria-label={`${title}. ${name} jämförs med ${comparisonName}. Enhet: ${unit}. Värden finns i tabellen nedanför.`}
        >
          <ResponsiveContainer width="100%" height="100%">
            <LineChart
              data={rows}
              margin={{ top: 16, right: 16, bottom: 8, left: 0 }}
              accessibilityLayer
            >
              <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--border)" />
              <XAxis
                dataKey="period"
                minTickGap={50}
                tick={{ fontSize: 12 }}
                tickFormatter={(v) => String(v).slice(0, 7)}
              />
              <YAxis
                domain={[axis.minimum, axis.maximum]}
                ticks={axis.ticks}
                width={65}
                tick={{ fontSize: 12 }}
                tickFormatter={(v) => afNumber(v)}
              />
              <Tooltip
                formatter={(v: number, label: string) => [
                  `${afNumber(v, unit === "%" ? 1 : 0)} ${unit}`,
                  label,
                ]}
                labelFormatter={(v) => `Månad ${v}`}
                contentStyle={{ borderRadius: 8, borderColor: "var(--border)" }}
              />

              <Line
                name={name}
                type="linear"
                dataKey="selected"
                stroke="var(--chart-1)"
                strokeWidth={2.5}
                dot={false}
                connectNulls={false}
                isAnimationActive={false}
              />
              <Line
                hide={!showComparison}
                name={comparisonName}
                type="linear"
                dataKey="country"
                stroke="var(--chart-3)"
                strokeWidth={2.5}
                dot={false}
                connectNulls={false}
                isAnimationActive={false}
              />
            </LineChart>
          </ResponsiveContainer>
        </div>
      )}
      <div className="mt-4 flex flex-wrap justify-center gap-5 text-sm">
        <span className="inline-flex items-center gap-2">
          <span aria-hidden="true" className="h-1 w-5 bg-[var(--chart-1)]" />
          {name}
        </span>
        {hasComparison && (
          <button
            type="button"
            className="inline-flex items-center gap-2 underline underline-offset-4"
            aria-pressed={showComparison}
            onClick={() => setShowComparison(!showComparison)}
          >
            <span aria-hidden="true" className="h-1 w-5 bg-[var(--chart-3)]" />
            {showComparison ? "Dölj" : "Visa"} {comparisonName.toLowerCase()}
          </button>
        )}
      </div>
      <div className="mt-4 flex flex-wrap justify-center gap-5 border-t border-border pt-4 text-sm text-brand-dark">
        <button
          type="button"
          className="underline underline-offset-4"
          onClick={() => setTable(!table)}
          aria-expanded={table}
        >
          {table ? "Dölj datatabell" : "Visa datatabell"}
        </button>
        <button type="button" className="underline underline-offset-4" onClick={download}>
          Ladda ned CSV
        </button>
      </div>
      {table && (
        <div className="mt-4 max-h-80 overflow-auto">
          <table className="w-full text-sm">
            <caption className="sr-only">
              {title}, {unit}
            </caption>
            <thead>
              <tr>
                <th scope="col" className="p-2 text-left">
                  Månad
                </th>
                <th scope="col">{name}</th>
                <th scope="col">{comparisonName}</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.period} className="border-t border-border">
                  <th scope="row" className="p-2 text-left font-normal">
                    {r.period}
                  </th>
                  <td className="text-center">
                    {afNumber(r.selectedSuppressed ? "<5" : r.selected, unit === "%" ? 1 : 0)}
                  </td>
                  <td className="text-center">
                    {afNumber(r.countrySuppressed ? "<5" : r.country, unit === "%" ? 1 : 0)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
