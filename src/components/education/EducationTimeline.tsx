import { educationAxis } from "@/lib/education-axis";
import { educationGenderColor } from "@/lib/education-colors";
import { useId, useState } from "react";
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { formatUkaValue, ukaComparisonTimeline, type UkaRow } from "@/lib/uka-view";

const programDashes = [undefined, "7 4", "2 4"];
export function EducationTimeline({
  rows,
  unit,
  valueAxisLabel,
  programs = [],
}: {
  rows: UkaRow[];
  unit: string;
  valueAxisLabel: string;
  programs?: string[];
}) {
  const id = useId();
  const [hidden, setHidden] = useState<string[]>([]);
  const data = ukaComparisonTimeline(rows, programs);
  const visible = data.series.filter((s) => !hidden.includes(s.key));
  const values = data.panels.flatMap((panel) =>
    panel.rows.flatMap((r) =>
      visible.map((s) => r[s.key]).filter((v): v is number => typeof v === "number"),
    ),
  );
  const axis = educationAxis(values, unit);
  const timeAxisLabel =
    data.semester || data.labels.every((label) => /^\d{4}$/.test(label)) ? "År" : "Period";
  return (
    <>
      <div className="mb-4 flex flex-wrap gap-2" aria-label="Visa eller dölj serier">
        {data.series.map((s) => (
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
                borderTopStyle: programs.length
                  ? (["solid", "dashed", "dotted"][programs.indexOf(s.category)] as
                      "solid" | "dashed" | "dotted")
                  : s.gender === "Män"
                    ? "dashed"
                    : "solid",
                borderTopColor: educationGenderColor(s.gender),
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
            {data.semester && <h4 className="mb-2 text-base font-semibold">{panel.name}</h4>}
            <div className="h-80 w-full" data-export-title={data.semester ? panel.name : undefined}>
              <ResponsiveContainer width="100%" height="100%">
                <LineChart
                  data={panel.rows}
                  syncId={id}
                  syncMethod="value"
                  accessibilityLayer
                  margin={{ left: 16, right: 18, top: 12, bottom: 12 }}
                >
                  <CartesianGrid stroke="var(--border)" vertical={false} />
                  <XAxis
                    dataKey="period"
                    height={50}
                    label={{
                      value: timeAxisLabel,
                      position: "insideBottom",
                      offset: 0,
                      fill: "var(--ink)",
                      fontSize: 14,
                    }}
                    interval="preserveStartEnd"
                    tick={{ fill: "var(--ink)", fontSize: 14 }}
                    padding={{ left: 12, right: 12 }}
                  />
                  <YAxis
                    domain={[0, axis.maximum]}
                    ticks={axis.ticks}
                    interval={0}
                    width={100}
                    label={{
                      value: valueAxisLabel,
                      angle: -90,
                      position: "insideLeft",
                      offset: 0,
                      fill: "var(--ink)",
                      fontSize: 14,
                      style: { textAnchor: "middle" },
                    }}
                    tick={{ fill: "var(--ink)", fontSize: 14 }}
                    tickFormatter={(v: number) =>
                      v.toLocaleString("sv-SE", { maximumFractionDigits: 0 })
                    }
                  />
                  <Tooltip
                    isAnimationActive={false}
                    formatter={(value: number, name: string) => [formatUkaValue(value, unit), name]}
                    labelFormatter={(label) =>
                      data.semester
                        ? `Period: ${panel.name.startsWith("Vår") ? "VT" : "HT"} ${label}`
                        : `${/^\d{4}$/.test(String(label)) ? "År" : "Period"}: ${label}`
                    }
                    contentStyle={{
                      background: "var(--surface)",
                      maxWidth: 280,
                      whiteSpace: "normal",
                      overflowWrap: "anywhere",
                      border: "1px solid var(--border)",
                      borderRadius: "var(--radius)",
                    }}
                    itemStyle={{ whiteSpace: "normal" }}
                  />
                  {data.series.map((s) => (
                    <Line
                      key={s.key}
                      dataKey={s.key}
                      name={s.label}
                      hide={hidden.includes(s.key)}
                      stroke={educationGenderColor(s.gender)}
                      strokeWidth={3}
                      strokeDasharray={
                        programs.length
                          ? programDashes[programs.indexOf(s.category)]
                          : s.gender === "Män"
                            ? "7 4"
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
      {!visible.length && (
        <p className="mt-3 text-sm">
          Alla serier är dolda. Klicka på en serie ovanför diagrammen för att visa den.
        </p>
      )}
    </>
  );
}
