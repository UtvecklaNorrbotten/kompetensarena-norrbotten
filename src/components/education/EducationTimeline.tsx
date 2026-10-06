import { useId, useState } from "react";
import {
  CartesianGrid,
  Line,
  LineChart,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { formatUkaValue, ukaComparisonTimeline, type UkaRow } from "@/lib/uka-view";

const colors = ["var(--chart-1)", "var(--chart-4)", "var(--chart-3)"];
export function EducationTimeline({
  rows,
  unit,
  programs = [],
}: {
  rows: UkaRow[];
  unit: string;
  programs?: string[];
}) {
  const id = useId();
  const [hidden, setHidden] = useState<string[]>([]);
  const [hover, setHover] = useState<string | null>(null);
  const data = ukaComparisonTimeline(rows, programs);
  const visible = data.series.filter((s) => !hidden.includes(s.key));
  const values = data.panels.flatMap((panel) =>
    panel.rows.flatMap((r) =>
      visible.map((s) => r[s.key]).filter((v): v is number => typeof v === "number"),
    ),
  );
  const maximum = unit === "%" ? 100 : Math.max(1, ...values) * 1.08;
  const active = data.labels.includes(hover ?? "") ? hover! : data.labels.at(-1);
  return (
    <>
      <div className="mb-4 flex flex-wrap gap-2" aria-label="Visa eller dölj serier">
        {data.series.map((s, i) => (
          <button
            key={s.key}
            type="button"
            aria-pressed={!hidden.includes(s.key)}
            onClick={() =>
              setHidden((old) =>
                old.includes(s.key) ? old.filter((k) => k !== s.key) : [...old, s.key],
              )
            }
            className={`rounded-md border border-border px-3 py-2 text-sm text-left ${hidden.includes(s.key) ? "opacity-50" : "font-semibold"}`}
          >
            <span
              aria-hidden
              style={{
                borderTopWidth: 3,
                borderTopStyle:
                  s.gender === "Män"
                    ? "dashed"
                    : s.gender === "Total" && programs.length
                      ? "dotted"
                      : "solid",
                borderTopColor:
                  colors[
                    programs.length
                      ? programs.indexOf(s.category) % colors.length
                      : i % colors.length
                  ],
              }}
              className="mr-2 inline-block w-5 align-middle"
            />
            {s.label}
          </button>
        ))}
      </div>
      <div
        className="grid gap-6 lg:grid-cols-2"
        style={!data.semester ? { gridTemplateColumns: "minmax(0, 1fr)" } : undefined}
      >
        {data.panels.map((panel) => (
          <section key={panel.name} aria-label={panel.name}>
            <h4 className="mb-2 text-base font-semibold">{panel.name}</h4>
            <div className="h-80 w-full" data-export-title={panel.name}>
              <ResponsiveContainer width="100%" height="100%">
                <LineChart
                  data={panel.rows}
                  syncId={id}
                  syncMethod="value"
                  accessibilityLayer
                  margin={{ left: 0, right: 18, top: 12, bottom: 12 }}
                  onMouseMove={(state) => {
                    if (state.activeLabel != null) setHover(String(state.activeLabel));
                  }}
                  onMouseLeave={() => setHover(null)}
                >
                  <CartesianGrid stroke="var(--border)" vertical={false} />
                  <XAxis
                    dataKey="period"
                    interval="preserveStartEnd"
                    tick={{ fill: "var(--ink)", fontSize: 14 }}
                    padding={{ left: 12, right: 12 }}
                  />
                  <YAxis
                    domain={[0, maximum]}
                    width={75}
                    tick={{ fill: "var(--ink)", fontSize: 14 }}
                    tickFormatter={(v) => formatUkaValue(v, unit)}
                  />
                  <Tooltip content={() => null} />
                  {active && (
                    <ReferenceLine x={active} stroke="var(--ink-muted)" strokeDasharray="3 3" />
                  )}
                  {data.series.map((s, i) => (
                    <Line
                      key={s.key}
                      dataKey={s.key}
                      name={s.label}
                      hide={hidden.includes(s.key)}
                      stroke={
                        colors[
                          programs.length
                            ? programs.indexOf(s.category) % colors.length
                            : i % colors.length
                        ]
                      }
                      strokeWidth={3}
                      strokeDasharray={
                        s.gender === "Män"
                          ? "7 4"
                          : s.gender === "Total" && programs.length
                            ? "2 4"
                            : undefined
                      }
                      dot={{ r: 3 }}
                      activeDot={{ r: 5 }}
                      connectNulls={false}
                      isAnimationActive={false}
                    />
                  ))}
                </LineChart>
              </ResponsiveContainer>
            </div>
          </section>
        ))}
      </div>
      <div className="mt-4 overflow-x-auto rounded-lg border border-border p-3">
        <p className="mb-2 text-sm font-semibold">
          {active ?? "Inga perioder"} · för musen över ett diagram för att jämföra samma år
        </p>
        <table className="w-full text-sm text-left">
          <thead>
            <tr>
              <th scope="col" className="p-2">
                Serie
              </th>
              {data.panels.map((p) => (
                <th key={p.name} scope="col" className="p-2 text-right">
                  {p.name}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {visible.map((s) => (
              <tr key={s.key} className="border-t border-border">
                <th scope="row" className="p-2 font-normal">
                  {s.label}
                </th>
                {data.panels.map((p) => (
                  <td key={p.name} className="p-2 text-right whitespace-nowrap">
                    {formatUkaValue(
                      (p.rows.find((r) => r["period"] === active)?.[s.key] as number | null) ??
                        null,
                      unit,
                    )}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
        {!visible.length && (
          <p className="text-sm">
            Alla serier är dolda. Klicka på en serie ovanför diagrammen för att visa den.
          </p>
        )}
      </div>
    </>
  );
}
