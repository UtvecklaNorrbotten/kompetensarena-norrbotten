import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import type { TimeSeriesPoint } from "@/data/types";

type TimeSeriesChartProps = {
  data: TimeSeriesPoint[];
  unit: string;
  /** Beskrivning för skärmläsare. */
  ariaLabel: string;
};

/**
 * Återanvändbart tidsseriediagram. Komponenten känner inte till någon
 * specifik indikator – den tar emot datapunkter och enhet som props.
 * Recharts är inkapslat här, så biblioteket kan bytas utan att sidor ändras.
 */
export function TimeSeriesChart({ data, unit, ariaLabel }: TimeSeriesChartProps) {
  return (
    <figure className="w-full" role="img" aria-label={ariaLabel}>
      <div className="h-72 w-full md:h-80">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={data} margin={{ top: 8, right: 16, bottom: 8, left: -12 }}>
            <CartesianGrid stroke="var(--border)" vertical={false} />
            <XAxis
              dataKey="label"
              tickLine={false}
              axisLine={{ stroke: "var(--border)" }}
              tick={{ fill: "var(--ink-muted)", fontSize: 13 }}
            />
            <YAxis
              tickLine={false}
              axisLine={false}
              width={56}
              tick={{ fill: "var(--ink-muted)", fontSize: 13 }}
            />
            <Tooltip
              formatter={(value: number) => [`${value} ${unit}`, ""]}
              contentStyle={{
                borderRadius: "var(--radius)",
                border: "1px solid var(--border)",
                background: "var(--surface)",
                color: "var(--ink)",
              }}
            />
            <Line
              type="monotone"
              dataKey="value"
              stroke="var(--chart-1)"
              strokeWidth={2.5}
              dot={{ r: 3, fill: "var(--chart-1)" }}
              activeDot={{ r: 5 }}
            />
          </LineChart>
        </ResponsiveContainer>
      </div>
      <figcaption className="mt-3 text-sm text-ink-muted">Enhet: {unit}</figcaption>
    </figure>
  );
}
