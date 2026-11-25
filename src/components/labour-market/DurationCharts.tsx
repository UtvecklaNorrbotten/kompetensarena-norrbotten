import {
  Bar,
  BarChart,
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { countAxis } from "@/lib/education-axis";
import {
  afPeriod,
  bandLabels,
  durationBands,
  durationLabels,
  durationText,
  durationValue,
  formatDuration,
  type DurationMeasure,
  type DurationRow,
  type DurationUnit,
} from "@/lib/af-duration";

const durationColors = ["var(--chart-5)", "var(--chart-3)", "var(--chart-2)", "var(--chart-1)"];
export function DurationCharts({
  rows,
  benchmark,
  measure,
  unit,
  chosenName,
}: {
  rows: DurationRow[];
  benchmark: DurationRow[];
  measure: DurationMeasure;
  unit: DurationUnit;
  chosenName: string;
}) {
  const reference = new Map(benchmark.map((r) => [r.period, r]));
  const history = rows.map((r) => ({
    period: r.period,
    chosen: durationValue(r, measure, unit),
    riket: durationValue(reference.get(r.period), measure, unit),
  }));
  const axis =
    unit === "share"
      ? { maximum: 100, ticks: [0, 20, 40, 60, 80, 100] }
      : countAxis(
          history.flatMap((r) => [r.chosen, r.riket]).filter((v): v is number => v !== null),
        );
  const stack = rows.map((r) => ({
    period: r.period,
    ...Object.fromEntries(durationBands(r, unit).map((v, i) => [`band${i}`, v])),
  }));
  const missingBands = rows.filter((r) => durationBands(r, unit).some((v) => v === null)).length;
  const stackAxis =
    unit === "share"
      ? { maximum: 100, ticks: [0, 20, 40, 60, 80, 100] }
      : countAxis(rows.flatMap((r) => (r.total === null ? [] : [r.total])));
  return (
    <>
      <div
        className="h-80 min-w-0"
        role="img"
        aria-label={`Utveckling över tid: ${durationLabels[measure]}. ${unit === "share" ? "Andel" : "Antal personer"}. Värden finns i tabellen nedan.`}
      >
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={history} margin={{ top: 12, right: 16, bottom: 4, left: 6 }}>
            <CartesianGrid vertical={false} stroke="var(--border)" />
            <XAxis dataKey="period" minTickGap={55} tickFormatter={(v) => String(v).slice(0, 4)} />
            <YAxis
              domain={[0, axis.maximum]}
              ticks={axis.ticks}
              width={65}
              tickFormatter={(v) => formatDuration(v, unit)}
            />
            <Tooltip
              labelFormatter={(v) => afPeriod(String(v))}
              formatter={(v: number) => formatDuration(v, unit)}
            />
            <Legend />
            {["2023-01", "2026-01"].map((p) => (
              <ReferenceLine key={p} x={p} stroke="var(--chart-4)" strokeDasharray="4 4" />
            ))}
            <Line
              type="linear"
              dataKey="chosen"
              name={chosenName}
              stroke="var(--chart-1)"
              strokeWidth={2.5}
              dot={false}
            />
            {benchmark.length > 0 && (
              <Line
                type="linear"
                dataKey="riket"
                name="Riket"
                stroke="var(--chart-3)"
                strokeWidth={2}
                dot={false}
                connectNulls={false}
              />
            )}
          </LineChart>
        </ResponsiveContainer>
      </div>
      <p className="mt-3 text-sm text-ink-muted">
        {durationLabels[measure]}. Linjeavbrott betyder att ett exakt värde saknas. Strecken
        markerar ändrad övre åldersgräns 2023 och 2026.
      </p>
      <h3 className="mt-10 text-xl">Hur fördelar sig tiden utan arbete?</h3>
      {missingBands > 0 && (
        <p className="mt-4 rounded-lg bg-brand-light p-4 text-sm" role="status">
          {missingBands} av {rows.length} månader kan inte fördelas exakt på alla fyra intervall på
          grund av sekretess eller saknade uppgifter.{" "}
          {missingBands === rows.length
            ? "Välj ett annat område, exempelvis Riket, för att se hela fördelningen."
            : "Dessa månader saknar staplar."}
        </p>
      )}
      {missingBands < rows.length && (
        <div
          className="mt-6 h-96 min-w-0"
          role="img"
          aria-label="Staplad utveckling av fyra ömsesidigt uteslutande längdintervall. Värden finns i tabellen nedan."
        >
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={stack} margin={{ top: 12, right: 16, bottom: 4, left: 6 }}>
              <CartesianGrid vertical={false} stroke="var(--border)" />
              <XAxis
                dataKey="period"
                minTickGap={55}
                tickFormatter={(v) => String(v).slice(0, 4)}
              />
              <YAxis
                domain={[0, stackAxis.maximum]}
                ticks={stackAxis.ticks}
                width={65}
                tickFormatter={(v) => formatDuration(v, unit)}
              />
              <Tooltip
                labelFormatter={(v) => afPeriod(String(v))}
                formatter={(v: number) => formatDuration(v, unit)}
              />
              <Legend />
              {bandLabels.map((name, i) => (
                <Bar
                  key={name}
                  dataKey={`band${i}`}
                  name={name}
                  stackId="duration"
                  stroke={durationColors[i]}
                  fill={durationColors[i]}
                />
              ))}
            </BarChart>
          </ResponsiveContainer>
        </div>
      )}
      <p className="mt-3 text-sm text-ink-muted">
        Intervallen räknas som differenser mellan källans överlappande mått. En månad visas bara när
        alla fyra intervall kan beräknas exakt.
      </p>
      <details className="mt-6">
        <summary className="cursor-pointer text-brand-dark underline underline-offset-4">
          Visa tidsserien som tabell
        </summary>
        <div className="mt-4 max-h-96 overflow-auto">
          <table className="w-full text-left text-sm">
            <caption className="sr-only">Tid utan arbete i valt område</caption>
            <thead>
              <tr>
                <th scope="col">Månad</th>
                <th scope="col">{durationLabels[measure]}</th>
                {bandLabels.map((n) => (
                  <th key={n} scope="col" className="p-2">
                    {n}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.period} className="border-t border-border">
                  <th scope="row" className="py-2">
                    {r.period}
                  </th>
                  <td>{durationText(r, measure, unit)}</td>
                  {durationBands(r, unit).map((v, i) => (
                    <td key={i} className="p-2">
                      {v === null ? "Ej beräkningsbart" : formatDuration(v, unit)}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </details>
    </>
  );
}
