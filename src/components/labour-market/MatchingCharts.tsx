import { useState } from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { educationAxis } from "@/lib/education-axis";
import { matchingNumber } from "@/lib/matching";

export type MatchingPoint = {
  code: string;
  label: string;
  value: number | null;
  comparison?: number | null | undefined;
};
export function MatchingTable({
  rows,
  unit,
  name,
}: {
  rows: MatchingPoint[];
  unit: string;
  name: string;
}) {
  const [open, setOpen] = useState(false);
  function download() {
    const quote = (value: unknown) => `"${String(value ?? "").replaceAll('"', '""')}"`;
    const text = [
      ["Urval", name, "Riket", "Enhet"],
      ...rows.map((r) => [
        r.label,
        matchingNumber(r.value, 2),
        matchingNumber(r.comparison, 2),
        unit,
      ]),
    ]
      .map((r) => r.map(quote).join(";"))
      .join("\r\n");
    const url = URL.createObjectURL(
      new Blob(["\uFEFF" + text], { type: "text/csv;charset=utf-8" }),
    );
    const link = document.createElement("a");
    link.href = url;
    link.download = "matchning.csv";
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  return (
    <div className="mt-6 border-t border-border pt-4">
      <div className="flex flex-wrap gap-5">
        <button
          type="button"
          className="underline"
          aria-expanded={open}
          onClick={() => setOpen(!open)}
        >
          Visa datatabell
        </button>
        <button type="button" className="underline" onClick={download}>
          Ladda ner CSV
        </button>
      </div>
      {open && (
        <div className="mt-4 max-h-96 overflow-auto">
          <table className="w-full text-left text-sm">
            <caption className="sr-only">
              {name}, {unit}
            </caption>
            <thead>
              <tr>
                <th className="p-2">Urval</th>
                <th className="p-2">
                  {name} ({unit})
                </th>
                {rows.some((r) => r.comparison !== undefined) && (
                  <th className="p-2">Riket ({unit})</th>
                )}
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.code} className="border-t border-border">
                  <th className="p-2 font-normal">{r.label}</th>
                  <td className="p-2">{matchingNumber(r.value)}</td>
                  {rows.some((v) => v.comparison !== undefined) && (
                    <td className="p-2">{matchingNumber(r.comparison)}</td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
export function MatchingHistory({
  rows,
  unit,
  name,
}: {
  rows: MatchingPoint[];
  unit: string;
  name: string;
}) {
  const [compare, setCompare] = useState(true);
  const axis = educationAxis(
    rows
      .flatMap((r) => [r.value, compare ? r.comparison : null])
      .filter((v): v is number => v != null),
    unit,
  );
  return (
    <>
      <label className="mb-5 flex items-center gap-2">
        <input type="checkbox" checked={compare} onChange={(e) => setCompare(e.target.checked)} />{" "}
        Jämför med riket
      </label>
      {rows.some((r) => r.value !== null) ? (
        <div
          className="h-80"
          role="img"
          aria-label={`${name}. Exakta värden finns i datatabellen.`}
        >
          <ResponsiveContainer width="100%" height="100%">
            <LineChart
              data={rows}
              margin={{ top: 15, left: 0, right: 20, bottom: 10 }}
              accessibilityLayer
            >
              <CartesianGrid vertical={false} stroke="var(--border)" strokeDasharray="3 3" />
              <XAxis dataKey="label" />
              <YAxis
                domain={[axis.minimum, axis.maximum]}
                ticks={axis.ticks}
                width={65}
                tickFormatter={(v) => matchingNumber(v, 0)}
              />
              <Tooltip
                formatter={(v: number, label: string) => [`${matchingNumber(v)} ${unit}`, label]}
              />
              <Line
                dataKey="value"
                name={name}
                stroke="var(--chart-1)"
                strokeWidth={3}
                dot={false}
                connectNulls={false}
                isAnimationActive={false}
              />
              <Line
                hide={!compare}
                dataKey="comparison"
                name="Riket"
                stroke="var(--chart-3)"
                strokeWidth={3}
                dot={false}
                connectNulls={false}
                isAnimationActive={false}
              />
            </LineChart>
          </ResponsiveContainer>
        </div>
      ) : (
        <p>Uppgift saknas för valt urval.</p>
      )}
      <MatchingTable rows={rows} unit={unit} name={name} />
    </>
  );
}
export function MatchingRanking({
  rows,
  unit,
  name,
  onSelect,
}: {
  rows: MatchingPoint[];
  unit: string;
  name: string;
  onSelect?: (code: string) => void;
}) {
  const [all, setAll] = useState(false);
  const sorted = [...rows].sort((a, b) => (b.value ?? -Infinity) - (a.value ?? -Infinity));
  const visible = (all ? sorted : sorted.slice(0, 5)).filter((r) => r.value !== null);
  const axis = educationAxis(
    visible.flatMap((r) => r.value ?? []),
    unit,
  );
  return (
    <>
      <h3 className="mb-4 text-lg">{all ? "Alla grupper" : "Topp 5"}</h3>
      {visible.length ? (
        <div
          style={{ height: Math.max(260, visible.length * 65) }}
          role="img"
          aria-label={`${name}. Välj en rad i listan nedan för fördjupning.`}
        >
          <ResponsiveContainer width="100%" height="100%">
            <BarChart
              layout="vertical"
              data={visible}
              margin={{ right: 24, left: 0 }}
              accessibilityLayer
            >
              <CartesianGrid horizontal={false} stroke="var(--border)" />
              <XAxis
                type="number"
                domain={[0, axis.maximum]}
                ticks={axis.ticks.filter((v) => v >= 0)}
                tickFormatter={(v) => matchingNumber(v, 0)}
              />
              <YAxis
                type="category"
                dataKey="label"
                width={190}
                tick={{ fontSize: 12 }}
                tickFormatter={(v: string) => (v.length > 29 ? v.slice(0, 28) + "…" : v)}
              />
              <Tooltip formatter={(v: number) => [`${matchingNumber(v)} ${unit}`, name]} />
              <Bar
                dataKey="value"
                name={name}
                fill="var(--chart-1)"
                maxBarSize={28}
                isAnimationActive={false}
              />
            </BarChart>
          </ResponsiveContainer>
        </div>
      ) : (
        <p>Uppgift saknas för valt urval.</p>
      )}
      {onSelect && (
        <div className="mt-4 flex max-h-44 flex-wrap gap-2 overflow-auto">
          {(all ? sorted : sorted.slice(0, 5)).map((r) => (
            <button
              key={r.code}
              type="button"
              className="rounded border border-border px-3 py-2 text-left text-sm hover:bg-brand-light"
              onClick={() => onSelect(r.code)}
            >
              {r.label}
            </button>
          ))}
        </div>
      )}
      {rows.length > 5 && (
        <div className="mt-6 flex items-center gap-4">
          <span className="h-px flex-1 bg-border" />
          <button
            type="button"
            className="underline"
            aria-expanded={all}
            onClick={() => setAll(!all)}
          >
            {all ? "Visa topp 5" : "Visa alla"}
          </button>
          <span className="h-px flex-1 bg-border" />
        </div>
      )}
      <MatchingTable rows={sorted} unit={unit} name={name} />
    </>
  );
}
