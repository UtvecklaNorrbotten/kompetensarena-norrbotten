import { useState } from "react";
import {
  BarChart,
  Bar,
  Cell,
  CartesianGrid,
  LineChart,
  Line,
  ResponsiveContainer,
  ReferenceLine,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { countAxis } from "@/lib/education-axis";
import { employmentNumber } from "@/lib/employment";
type Row = {
  label: string;
  value: number | null;
  other?: number | null;
  status?: string;
  otherStatus?: string;
  segment?: string;
};
export function EmploymentChart({
  rows,
  unit,
  rank = false,
  name,
  other = "Riket",
  filename = "sysselsattning",
  source = "",
}: {
  rows: Row[];
  unit: string;
  rank?: boolean;
  name: string;
  other?: string;
  filename?: string;
  source?: string;
}) {
  const [table, setTable] = useState(false);
  const hasOther = !rank && rows.some((r) => r.other != null);
  const [compare, setCompare] = useState(false);
  const axis = countAxis(
    rows.flatMap((r) => [r.value, compare ? r.other : null]).filter((v): v is number => v != null),
  );
  const decimals = unit === "%" ? 1 : 0;
  const segments = [...new Set(rows.map((r) => r.segment ?? "all"))];
  const chartRows = rows.map((r) => ({
    ...r,
    ...Object.fromEntries(
      segments.flatMap((s, i) => [
        [`v${i}`, (r.segment ?? "all") === s ? r.value : null],
        [`o${i}`, (r.segment ?? "all") === s ? r.other : null],
      ]),
    ),
  }));
  const download = () => {
    const csv = [
      [
        rank ? "Kategori" : "Period",
        name,
        other,
        "Enhet",
        "SCB-status",
        ...(source ? ["Källa och urval"] : []),
      ],
      ...rows.map((r) => [
        r.label,
        r.value == null ? "Uppgift saknas" : employmentNumber(r.value, "", decimals),
        r.other == null ? "Uppgift saknas" : employmentNumber(r.other, r.otherStatus, decimals),
        unit,
        r.status ?? "",
        ...(source ? [source] : []),
      ]),
    ]
      .map((r) => r.map((v) => `"${String(v).replaceAll('"', '""')}"`).join(";"))
      .join("\r\n");
    const url = URL.createObjectURL(new Blob(["\uFEFF" + csv], { type: "text/csv;charset=utf-8" }));
    const a = document.createElement("a");
    a.href = url;
    a.download = `${filename}.csv`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };
  return (
    <>
      {rows.some((r) => r.value !== null) ? (
        <div
          role="img"
          aria-label={`${name}. Enhet: ${unit}. Exakta värden finns i datatabellen.`}
          style={{ height: rank ? Math.max(260, rows.length * 42) : 320 }}
          className="w-full min-w-0"
        >
          <ResponsiveContainer width="100%" height="100%">
            {rank ? (
              <BarChart
                data={rows}
                layout="vertical"
                margin={{ left: 0, right: 24, top: 12, bottom: 10 }}
                accessibilityLayer
              >
                <CartesianGrid horizontal={false} stroke="var(--border)" />
                <XAxis
                  type="number"
                  domain={[axis.minimum, axis.maximum]}
                  ticks={axis.ticks}
                  tickFormatter={(v) => employmentNumber(v, "", decimals)}
                />
                <YAxis
                  type="category"
                  dataKey="label"
                  width={150}
                  tick={{ fontSize: 12 }}
                  tickFormatter={(v) => (String(v).length > 23 ? String(v).slice(0, 22) + "…" : v)}
                />
                <Tooltip
                  wrapperStyle={{ maxWidth: "min(280px, 80vw)", whiteSpace: "normal" }}
                  contentStyle={{ overflowWrap: "anywhere", whiteSpace: "normal" }}
                  formatter={(v: number) => [`${employmentNumber(v, "", decimals)} ${unit}`, name]}
                />
                <Bar dataKey="value" isAnimationActive={false}>
                  {rows.map((r, i) => (
                    <Cell
                      key={i}
                      fill={r.value !== null && r.value < 0 ? "var(--chart-3)" : "var(--chart-1)"}
                    />
                  ))}
                </Bar>
              </BarChart>
            ) : (
              <LineChart
                data={chartRows}
                margin={{ top: 16, right: 15, left: 0, bottom: 8 }}
                accessibilityLayer
              >
                <CartesianGrid vertical={false} stroke="var(--border)" />
                <XAxis dataKey="label" minTickGap={50} />
                <YAxis
                  domain={[axis.minimum, axis.maximum]}
                  ticks={axis.ticks}
                  width={75}
                  tickFormatter={(v) => employmentNumber(v, "", decimals)}
                />
                <Tooltip
                  wrapperStyle={{ maxWidth: "min(280px, 80vw)", whiteSpace: "normal" }}
                  contentStyle={{ overflowWrap: "anywhere", whiteSpace: "normal" }}
                  formatter={(v: number, label: string) => [
                    `${employmentNumber(v, "", decimals)} ${unit}`,
                    label,
                  ]}
                />
                {segments.map((s, i) => (
                  <Line
                    key={s}
                    dataKey={`v${i}`}
                    name={name}
                    stroke="var(--chart-1)"
                    strokeWidth={2.5}
                    dot={rows.length <= 12 ? { r: 3 } : false}
                    connectNulls={false}
                    isAnimationActive={false}
                  />
                ))}
                {compare &&
                  segments.map((s, i) => (
                    <Line
                      key={`o-${s}`}
                      dataKey={`o${i}`}
                      name={other}
                      stroke="var(--chart-3)"
                      strokeWidth={2.5}
                      dot={rows.length <= 12 ? { r: 3 } : false}
                      connectNulls={false}
                      isAnimationActive={false}
                    />
                  ))}
                {segments.length > 1 &&
                  ["2022", "2024"]
                    .filter((y) => rows.some((r) => r.label === y))
                    .map((y) => (
                      <ReferenceLine
                        key={y}
                        x={y}
                        stroke="var(--ink-muted)"
                        strokeDasharray="4 4"
                        label={{ value: `Metod ${y}`, position: "insideTop", fontSize: 12 }}
                      />
                    ))}
              </LineChart>
            )}
          </ResponsiveContainer>
        </div>
      ) : (
        <p className="py-10 text-ink-muted">Det finns inga jämförbara uppgifter för urvalet.</p>
      )}
      <div className="mt-5 flex flex-wrap justify-center gap-5 text-sm text-brand-dark">
        {hasOther && (
          <button
            type="button"
            aria-pressed={compare}
            className="underline underline-offset-4"
            onClick={() => setCompare(!compare)}
          >
            {compare ? "Dölj" : "Visa"} {other}
          </button>
        )}
        <button
          type="button"
          aria-expanded={table}
          className="underline underline-offset-4"
          onClick={() => setTable(!table)}
        >
          {table ? "Dölj" : "Visa"} datatabell
        </button>
        <button type="button" className="underline underline-offset-4" onClick={download}>
          Ladda ned CSV
        </button>
      </div>
      {table && (
        <div className="mt-5 max-h-96 overflow-auto">
          <table className="w-full text-sm">
            <caption className="text-left pb-3">
              {name} ({unit})
            </caption>
            <thead>
              <tr>
                <th className="p-2 text-left">{rank ? "Kategori" : "Period"}</th>
                <th className="p-2 text-right">{name}</th>
                {hasOther && <th className="p-2 text-right">{other}</th>}
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) => (
                <tr key={i} className="border-t border-border">
                  <th scope="row" className="p-2 text-left font-normal">
                    {r.label}
                  </th>
                  <td className="p-2 text-right tabular-nums">
                    {employmentNumber(r.value, r.status, decimals)}
                  </td>
                  {hasOther && (
                    <td className="p-2 text-right tabular-nums">
                      {employmentNumber(r.other, r.otherStatus, decimals)}
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
