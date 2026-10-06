import { useId, useMemo, useState } from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { ExplainedTerm } from "@/components/ui/ExplainedTerm";
import { Switch } from "@/components/ui/switch";
import type { EducationIndicator } from "@/config/education";
import {
  dimensionLabels,
  periodLabel,
  periodOrder,
  selectUkaRows,
  type UkaFilters,
  type UkaRow,
} from "@/lib/uka-view";

const format = (value: number | null | undefined, unit: string) =>
  value == null
    ? "Uppgift saknas"
    : `${new Intl.NumberFormat("sv-SE", { maximumFractionDigits: unit === "antal" ? 0 : 1 }).format(value)}${unit === "%" ? " %" : ""}`;
const colors = ["var(--chart-1)", "var(--chart-4)", "var(--chart-3)"];

export function EducationFigure({
  indicator,
  rows,
  filters,
  university,
  fetched,
}: {
  indicator: EducationIndicator;
  rows: UkaRow[];
  filters: UkaFilters;
  university: string;
  fetched: string | null;
}) {
  const [detail, setDetail] = useState(false);
  const [showAll, setShowAll] = useState(false);
  const switchId = useId();
  const source = useMemo(
    () => rows.filter((r) => r.indicator_id === indicator.id),
    [rows, indicator.id],
  );
  const overview = useMemo(() => selectUkaRows(source, filters), [source, filters]);
  const selected = detail ? selectUkaRows(source, filters, true) : overview;
  const genderRows = selected.rows.filter((r) => r.gender === filters.gender);
  const periods = [...new Set(genderRows.map((r) => r.period))].sort(
    (a, b) => periodOrder(a) - periodOrder(b),
  );
  const latestPeriod = periods.at(-1);
  const latestOverview = overview.rows
    .filter((r) => r.gender === filters.gender)
    .sort((a, b) => periodOrder(a.period) - periodOrder(b.period))
    .at(-1);
  const useGenders =
    detail &&
    filters.gender === "Total" &&
    ["Kvinnor", "Män"].every((g) =>
      selected.rows.some((r) => r.period === latestPeriod && r.gender === g),
    );
  const series = useGenders ? ["Kvinnor", "Män"] : [filters.gender];
  const barRows = new Map<string, Record<string, string | number | null>>();
  for (const r of selected.rows) {
    if (r.period !== latestPeriod || !series.includes(r.gender)) continue;
    const label = r.category.replaceAll("|", " · ") || "Samtliga";
    const existing = barRows.get(label) ?? { category: label };
    existing[r.gender] = r.value;
    barRows.set(label, existing);
  }
  const allBars = [...barRows.values()].sort((a, b) => {
    const aValue = Math.max(
      ...series.map((g) => (typeof a[g] === "number" ? (a[g] as number) : -Infinity)),
    );
    const bValue = Math.max(
      ...series.map((g) => (typeof b[g] === "number" ? (b[g] as number) : -Infinity)),
    );
    return bValue - aValue;
  });
  const bars = showAll ? allBars : allBars.slice(0, 12);
  const lineData = genderRows.map((r) => ({ period: periodLabel(r.period), value: r.value }));
  const selectedFilters = Object.entries(filters.dimensions).filter(([, v]) => v);
  const ignored = selectedFilters.filter(([key]) => !selected.applied.includes(key));
  const hasValues = (
    detail
      ? selected.rows.filter((r) => r.period === latestPeriod && series.includes(r.gender))
      : genderRows
  ).some((r) => r.value !== null);
  const domain: [number, number | "auto"] = indicator.unit === "%" ? [0, 100] : [0, "auto"];

  return (
    <article className="rounded-xl border border-border bg-surface p-5 md:p-7">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="min-w-0">
          <h3 className="text-xl md:text-2xl">
            <ExplainedTerm term={indicator.title} explanation={indicator.definition} />
          </h3>
          <p className="mt-3 max-w-2xl text-sm leading-relaxed text-ink-muted">
            {indicator.explanation}
          </p>
        </div>
        <div className="flex shrink-0 items-center gap-2 text-xs">
          <span className={!detail ? "font-semibold text-brand-dark" : "text-ink-muted"}>
            Översikt
          </span>
          <Switch
            id={switchId}
            checked={detail}
            onCheckedChange={setDetail}
            aria-label={`Visa fördjupning för ${indicator.title}`}
          />
          <label
            htmlFor={switchId}
            className={`cursor-pointer ${detail ? "font-semibold text-brand-dark" : "text-ink-muted"}`}
          >
            Fördjupning
          </label>
        </div>
      </div>
      {latestOverview && !detail && (
        <div className="mt-6 flex flex-wrap items-baseline gap-x-3 gap-y-1">
          <strong className="text-3xl text-brand-dark">
            {format(latestOverview.value, indicator.unit)}
          </strong>
          <span className="text-sm text-ink-muted">
            {indicator.unit !== "%" ? indicator.unit : "etablerade"} ·{" "}
            {periodLabel(latestOverview.period)}
          </span>
        </div>
      )}
      <p className="mt-4 text-xs text-ink-muted">
        {university} · {filters.gender === "Total" ? "Samtliga" : filters.gender}
        {selectedFilters
          .filter(([key]) => selected.applied.includes(key))
          .map(([key, value]) => ` · ${dimensionLabels[key] ?? key}: ${value}`)
          .join("")}
      </p>
      {ignored.length > 0 && (
        <p className="mt-1 text-xs text-ink-muted">
          {ignored.map(([key]) => dimensionLabels[key] ?? key).join(", ")}: detta mått saknar
          uppdelningen och visas utan det urvalet.
        </p>
      )}
      {!hasValues ? (
        <div className="mt-5 rounded-lg bg-neutral-surface p-6 text-sm" role="status">
          {overview.ambiguous && !detail
            ? "Urvalet omfattar flera överlappande grupper. Precisera urvalet i sidans filter eller välj fördjupning för att se grupperna separat."
            : "Inga publicerade värden finns för detta urval. Ändra sidans filter för att se ett annat urval."}
        </div>
      ) : (
        <figure className="mt-6" aria-label={`${indicator.title}, ${university}`}>
          {detail ? (
            <>
              <p className="mb-4 text-sm">
                {dimensionLabels[selected.breakdown.split("|").at(-1) ?? ""] ?? "Uppdelning"} ·{" "}
                {periodLabel(latestPeriod ?? "")}
                {!showAll && allBars.length > 12 ? " · de 12 högsta värdena" : ""}
              </p>
              <div style={{ height: Math.max(240, bars.length * (useGenders ? 54 : 40) + 70) }}>
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart
                    accessibilityLayer
                    data={bars}
                    layout="vertical"
                    margin={{ left: 0, right: 16, top: 8, bottom: 8 }}
                  >
                    <CartesianGrid stroke="var(--border)" horizontal={false} />
                    <XAxis
                      type="number"
                      domain={domain}
                      tick={{ fill: "var(--ink-muted)", fontSize: 12 }}
                    />
                    <YAxis
                      type="category"
                      dataKey="category"
                      width={140}
                      tick={{ fill: "var(--ink-muted)", fontSize: 11 }}
                      tickFormatter={(v: string) => (v.length > 24 ? `${v.slice(0, 22)}…` : v)}
                      interval={0}
                    />
                    <Tooltip
                      formatter={(value: number) => format(value, indicator.unit)}
                      contentStyle={{
                        background: "var(--surface)",
                        border: "1px solid var(--border)",
                        borderRadius: "var(--radius)",
                      }}
                    />
                    {useGenders && <Legend />}
                    {series.map((gender, i) => (
                      <Bar
                        key={gender}
                        name={gender === "Total" ? "Samtliga" : gender}
                        dataKey={gender}
                        fill={colors[i] ?? colors[0]}
                        isAnimationActive={false}
                        radius={[0, 3, 3, 0]}
                      />
                    ))}
                  </BarChart>
                </ResponsiveContainer>
              </div>
              {allBars.length > 12 && (
                <button
                  type="button"
                  onClick={() => setShowAll(!showAll)}
                  className="mt-3 text-sm text-brand-dark underline"
                >
                  {showAll ? "Visa de 12 högsta värdena" : `Visa alla ${allBars.length} grupper`}
                </button>
              )}
            </>
          ) : (
            <div className="h-64 md:h-72">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart
                  accessibilityLayer
                  data={lineData}
                  margin={{ left: 0, right: 16, top: 8, bottom: 8 }}
                >
                  <CartesianGrid stroke="var(--border)" vertical={false} />
                  <XAxis
                    dataKey="period"
                    tick={{ fill: "var(--ink-muted)", fontSize: 12 }}
                    minTickGap={20}
                  />
                  <YAxis
                    domain={domain}
                    tick={{ fill: "var(--ink-muted)", fontSize: 12 }}
                    width={60}
                  />
                  <Tooltip
                    formatter={(value: number) => [format(value, indicator.unit), indicator.title]}
                    contentStyle={{
                      background: "var(--surface)",
                      border: "1px solid var(--border)",
                      borderRadius: "var(--radius)",
                    }}
                  />
                  <Line
                    dataKey="value"
                    name={indicator.title}
                    stroke="var(--chart-1)"
                    strokeWidth={3}
                    dot={{ r: 3 }}
                    isAnimationActive={false}
                    connectNulls={false}
                  />
                </LineChart>
              </ResponsiveContainer>
            </div>
          )}
          <figcaption className="mt-3 text-xs text-ink-muted">
            Enhet: {indicator.unit}.{" "}
            {detail
              ? "Uppdelningen visar senaste perioden inom tidsurvalet. Fullständiga namn och värden finns i tabellen."
              : "Varje punkt motsvarar en publicerad period. Saknade värden visas som luckor."}
          </figcaption>
          <details className="mt-5 border-t border-border pt-3">
            <summary className="cursor-pointer text-sm text-brand-dark">
              Visa värden som tabell
            </summary>
            <div className="mt-3 max-h-80 overflow-auto">
              <table className="w-full text-left text-xs">
                <caption className="sr-only">
                  {indicator.title} för {university}
                </caption>
                <thead>
                  <tr>
                    <th scope="col" className="p-2">
                      Period
                    </th>
                    <th scope="col" className="p-2">
                      Grupp
                    </th>
                    <th scope="col" className="p-2">
                      Kön
                    </th>
                    <th scope="col" className="p-2 text-right">
                      {indicator.unit}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {selected.rows
                    .filter((r) =>
                      detail
                        ? r.period === latestPeriod && series.includes(r.gender)
                        : r.gender === filters.gender,
                    )
                    .map((r) => (
                      <tr
                        key={`${r.period}|${r.category}|${r.gender}`}
                        className="border-t border-border"
                      >
                        <td className="p-2 whitespace-nowrap">{periodLabel(r.period)}</td>
                        <th scope="row" className="p-2 font-normal">
                          {r.category.replaceAll("|", " · ") || "Samtliga"}
                        </th>
                        <td className="p-2">{r.gender === "Total" ? "Samtliga" : r.gender}</td>
                        <td className="p-2 text-right whitespace-nowrap">
                          {format(r.value, indicator.unit)}
                        </td>
                      </tr>
                    ))}
                </tbody>
              </table>
            </div>
          </details>
        </figure>
      )}
      <div className="mt-5 flex flex-wrap justify-between gap-2 border-t border-border pt-3 text-xs text-ink-muted">
        <a
          href={`https://statistik-www.uka.se/export/?indicator=${indicator.ukaId}`}
          target="_blank"
          rel="noreferrer"
          className="text-brand-dark underline"
        >
          Källa: UKÄ · Högskolan i siffror
        </a>
        {fetched && <span>Senast hämtad: {fetched.slice(0, 10)}</span>}
      </div>
    </article>
  );
}
