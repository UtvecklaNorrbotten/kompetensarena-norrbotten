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
import { demandNumber, demandValue, type DemandPoint } from "@/lib/labour-demand";
const months = ["Jan", "Feb", "Mar", "Apr", "Maj", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dec"];
const colors = ["var(--chart-1)", "var(--chart-3)", "var(--chart-2)", "var(--ink-muted)"];
export function DemandSeason({ rows, period }: { rows: DemandPoint[]; period: string }) {
  const [table, setTable] = useState(false);
  const year = Number(period.slice(0, 4));
  const years = Array.from({ length: 4 }, (_, i) => String(year - 3 + i));
  const index = new Map(rows.map((r) => [r.period, r.value]));
  const data = months.map((month, i) => ({
    month,
    ...Object.fromEntries(
      years.map((y) => [y, demandValue(index.get(`${y}-${String(i + 1).padStart(2, "0")}`))]),
    ),
  }));
  const axis = countAxis(
    data
      .flatMap((r) => years.map((y) => (r as Record<string, unknown>)[y]))
      .filter((v): v is number => typeof v === "number"),
  );
  return (
    <>
      <div
        className="h-80"
        role="img"
        aria-label="Månadsvärden för de fyra senaste åren. Datatabell finns nedanför."
      >
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={data} margin={{ right: 15, top: 15 }} accessibilityLayer>
            <CartesianGrid vertical={false} stroke="var(--border)" strokeDasharray="3 3" />
            <XAxis dataKey="month" tick={{ fontSize: 12 }} />
            <YAxis
              width={65}
              domain={[0, axis.maximum]}
              ticks={axis.ticks}
              tickFormatter={(v) => demandNumber(v)}
              tick={{ fontSize: 12 }}
            />
            <Tooltip formatter={(v: number) => demandNumber(v)} />
            {years.map((y, i) => (
              <Line
                key={y}
                dataKey={y}
                name={y}
                stroke={colors[i]}
                strokeDasharray={i === 1 ? "6 3" : i === 2 ? "2 3" : undefined}
                strokeWidth={i === 3 ? 3 : 2}
                dot={false}
                connectNulls={false}
                isAnimationActive={false}
              />
            ))}
          </LineChart>
        </ResponsiveContainer>
      </div>
      <div className="mt-4 flex justify-center gap-4 text-sm">
        {years.map((y, i) => (
          <span key={y} className="flex items-center gap-2">
            <span style={{ background: colors[i] }} className="h-1 w-4" />
            {y}
          </span>
        ))}
      </div>
      <button
        type="button"
        className="mx-auto mt-5 block text-sm text-brand-dark underline underline-offset-4"
        aria-expanded={table}
        onClick={() => setTable(!table)}
      >
        {table ? "Dölj" : "Visa"} datatabell
      </button>
      {table && (
        <div className="mt-4 overflow-auto">
          <table className="w-full text-sm">
            <caption className="sr-only">Säsongsmönster, antal platser</caption>
            <thead>
              <tr>
                <th scope="col">Månad</th>
                {years.map((y) => (
                  <th scope="col" key={y}>
                    {y}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {months.map((m, i) => (
                <tr key={m} className="border-t border-border">
                  <th scope="row" className="p-2 text-left">
                    {m}
                  </th>
                  {years.map((y) => (
                    <td key={y} className="text-center">
                      {demandNumber(index.get(`${y}-${String(i + 1).padStart(2, "0")}`))}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
