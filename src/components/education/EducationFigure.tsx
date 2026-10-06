import { Download } from "lucide-react";
import {
  educationCsv,
  downloadBlob,
  exportFilename,
  saveEducationPng,
  wrapChartLabel,
} from "@/lib/education-export";
import { useId, useMemo, useRef, useState } from "react";
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
  formatUkaValue as format,
  periodLabel,
  periodOrder,
  selectUkaRows,
  ukaGenderSeries,
  ukaGenderTimeline,
  type UkaFilters,
  type UkaRow,
} from "@/lib/uka-view";

const colors = ["var(--chart-1)", "var(--chart-4)", "var(--chart-3)"];

function CategoryTick({
  x = 0,
  y = 0,
  payload,
}: {
  x?: number;
  y?: number;
  payload?: { value?: string };
}) {
  const lines = wrapChartLabel(String(payload?.value ?? ""), 26);
  return (
    <g transform={`translate(${x},${y})`}>
      <text textAnchor="end" fontSize={13} fontWeight={400} fill="var(--ink)">
        {lines.map((line, i) => (
          <tspan key={i} x={-10} dy={i === 0 ? 4 - (lines.length - 1) * 9 : 18}>
            {line}
          </tspan>
        ))}
      </text>
    </g>
  );
}

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
  const chartRef = useRef<HTMLDivElement>(null);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState("");
  const source = useMemo(
    () => rows.filter((r) => r.indicator_id === indicator.id),
    [rows, indicator.id],
  );
  const overview = useMemo(() => selectUkaRows(source, filters), [source, filters]);
  const selected = detail ? selectUkaRows(source, filters, true) : overview;
  const series = ukaGenderSeries(selected.rows);
  const genderRows = selected.rows.filter((r) => series.includes(r.gender));
  const periods = [...new Set(selected.rows.map((r) => r.period))].sort(
    (a, b) => periodOrder(a) - periodOrder(b),
  );
  const latestPeriod = periods.at(-1);
  const latestOverview = overview.rows
    .filter((r) => r.gender === filters.gender)
    .sort((a, b) => periodOrder(a.period) - periodOrder(b.period))
    .at(-1);
  const useGenders = series.includes("Kvinnor");
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
  const lineData = ukaGenderTimeline(selected.rows, series);
  const selectedFilters = Object.entries(filters.dimensions).filter(([, v]) => v);
  const ignored = selectedFilters.filter(([key]) => !selected.applied.includes(key));
  const hasValues = (
    detail
      ? selected.rows.filter((r) => r.period === latestPeriod && series.includes(r.gender))
      : genderRows
  ).some((r) => r.value !== null);
  const domain: [number, number | "auto"] = indicator.unit === "%" ? [0, 100] : [0, "auto"];

  const tableRows = selected.rows.filter((r) => (detail ? r.period === latestPeriod : true));
  const filename =
    exportFilename(indicator.id, university) + (detail ? "-fordjupning" : "-oversikt");
  const contextText = `${university} · ${useGenders ? (series.includes("Total") ? "Kvinnor, män och total" : "Kvinnor och män") : "Samtliga"}${selectedFilters
    .filter(([key]) => selected.applied.includes(key))
    .map(([key, value]) => ` · ${dimensionLabels[key] ?? key}: ${value}`)
    .join("")}`;
  const rowHeight = Math.max(
    useGenders ? 90 : 48,
    ...bars.map((r) => wrapChartLabel(String(r["category"]), 26).length * 18 + 20),
  );
  async function saveFigure() {
    const svg = chartRef.current?.querySelector<SVGSVGElement>("svg.recharts-surface");
    if (!svg) {
      setSaveError("Figuren har inte laddats färdigt. Försök igen.");
      return;
    }
    setSaving(true);
    setSaveError("");
    try {
      await saveEducationPng(svg, filename, indicator.title, [
        contextText,
        indicator.explanation,
        ...(useGenders
          ? [
              `Grön: Kvinnor. Grå: Män (streckad linje i översikt).${series.includes("Total") ? " Gul: Samtliga." : ""}`,
            ]
          : []),
        `Enhet: ${indicator.unit}. ${detail ? `Period: ${periodLabel(latestPeriod ?? "")}. ${!showAll && allBars.length > 12 ? "De 12 högsta värdena visas." : "Alla grupper visas."}` : "Samtliga tillgängliga perioder visas."}`,
        ...(ignored.length
          ? [
              `Urval utan motsvarighet i måttet: ${ignored.map(([key]) => dimensionLabels[key] ?? key).join(", ")}.`,
            ]
          : []),
        `Källa: UKÄ, Högskolan i siffror${fetched ? `. Senast hämtad: ${fetched.slice(0, 10)}` : ""}`,
      ]);
    } catch (error) {
      setSaveError(error instanceof Error ? error.message : "Figuren kunde inte sparas.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <article className="rounded-xl border border-border bg-surface p-5 md:p-7">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="min-w-0 flex-1 basis-60">
          <h3 className="text-xl md:text-2xl">
            <ExplainedTerm term={indicator.title} explanation={indicator.definition} />
          </h3>
          <p className="mt-3 max-w-2xl text-base leading-relaxed text-ink">
            {indicator.explanation}
          </p>
        </div>
        <div className="flex shrink-0 flex-col items-end gap-4">
          <button
            type="button"
            onClick={saveFigure}
            disabled={!hasValues || saving}
            className="inline-flex items-center gap-2 rounded-md border border-border px-3 py-2 text-sm font-medium text-brand-dark hover:bg-brand-light disabled:opacity-50"
            aria-label={`Spara figur: ${indicator.title}`}
          >
            <Download className="size-4" aria-hidden />
            {saving ? "Sparar…" : "Spara figur"}
          </button>
          <div className="flex shrink-0 items-center gap-2 text-sm">
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
      </div>
      {saveError && (
        <p role="alert" className="mt-3 text-sm text-destructive">
          {saveError}
        </p>
      )}
      {latestOverview && !detail && (
        <div className="mt-6 flex flex-wrap items-baseline gap-x-3 gap-y-1">
          <strong className="text-3xl text-brand-dark">
            {format(latestOverview.value, indicator.unit)}
          </strong>
          <span className="text-sm text-ink-muted">
            Samtliga · {indicator.unit !== "%" ? indicator.unit : "etablerade"} ·{" "}
            {periodLabel(latestOverview.period)}
          </span>
        </div>
      )}
      <p className="mt-4 text-sm text-ink-muted">
        {university} ·{" "}
        {useGenders
          ? series.includes("Total")
            ? "Kvinnor, män och total"
            : "Kvinnor och män"
          : "Samtliga"}
        {selectedFilters
          .filter(([key]) => selected.applied.includes(key))
          .map(([key, value]) => ` · ${dimensionLabels[key] ?? key}: ${value}`)
          .join("")}
      </p>
      {!useGenders && hasValues && (
        <p className="mt-1 text-sm text-ink-muted">
          UKÄ saknar könsuppdelning i detta urval. Figuren visar samtliga.
        </p>
      )}
      {ignored.length > 0 && (
        <p className="mt-1 text-sm text-ink-muted">
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
              <div className="overflow-x-auto">
                <div
                  ref={chartRef}
                  className="min-w-[620px]"
                  style={{ height: Math.max(260, bars.length * rowHeight + 80) }}
                >
                  <ResponsiveContainer width="100%" height="100%">
                    <BarChart
                      accessibilityLayer
                      data={bars}
                      layout="vertical"
                      margin={{ left: 16, right: 32, top: 16, bottom: 16 }}
                    >
                      <CartesianGrid stroke="var(--border)" horizontal={false} />
                      <XAxis
                        type="number"
                        domain={domain}
                        tick={{ fill: "var(--ink)", fontSize: 14 }}
                      />
                      <YAxis
                        type="category"
                        dataKey="category"
                        width={230}
                        tick={<CategoryTick />}
                        interval={0}
                      />
                      <Tooltip
                        formatter={(value: number) => format(value, indicator.unit)}
                        contentStyle={{
                          background: "var(--surface)",
                          maxWidth: 280,
                          whiteSpace: "normal",
                          overflowWrap: "anywhere",
                          border: "1px solid var(--border)",
                          borderRadius: "var(--radius)",
                        }}
                      />
                      <Legend />
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
            <div className="overflow-x-auto">
              <div ref={chartRef} className="h-72 min-w-[620px] md:h-80">
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart
                    accessibilityLayer
                    data={lineData}
                    margin={{ left: 16, right: 32, top: 16, bottom: 16 }}
                  >
                    <CartesianGrid stroke="var(--border)" vertical={false} />
                    <XAxis
                      dataKey="period"
                      tick={{ fill: "var(--ink)", fontSize: 14 }}
                      minTickGap={20}
                      padding={{ left: 16, right: 24 }}
                      height={42}
                    />
                    <YAxis domain={domain} tick={{ fill: "var(--ink)", fontSize: 14 }} width={90} />
                    <Tooltip
                      formatter={(value: number, name: string) => [
                        format(value, indicator.unit),
                        name === "Total" ? "Samtliga" : name,
                      ]}
                      contentStyle={{
                        background: "var(--surface)",
                        maxWidth: 280,
                        whiteSpace: "normal",
                        overflowWrap: "anywhere",
                        border: "1px solid var(--border)",
                        borderRadius: "var(--radius)",
                      }}
                    />
                    <Legend />
                    {series.map((gender, i) => (
                      <Line
                        key={gender}
                        dataKey={gender}
                        name={gender === "Total" ? "Samtliga" : gender}
                        stroke={colors[i] ?? colors[0]}
                        strokeWidth={3}
                        strokeDasharray={gender === "Män" ? "7 4" : undefined}
                        dot={{ r: 3 }}
                        isAnimationActive={false}
                        connectNulls={false}
                      />
                    ))}
                  </LineChart>
                </ResponsiveContainer>
              </div>
            </div>
          )}
          <figcaption className="mt-3 text-sm text-ink-muted">
            Enhet: {indicator.unit}.{" "}
            {detail
              ? "Uppdelningen visar senaste tillgängliga perioden. Hela gruppnamnen visas med radbrytning."
              : "Varje punkt motsvarar en publicerad period. Saknade värden visas som luckor."}
          </figcaption>
          <div className="relative mt-5 border-t border-border pt-3">
            <button
              type="button"
              onClick={() =>
                downloadBlob(
                  new Blob([educationCsv(tableRows, indicator.title, indicator.unit)], {
                    type: "text/csv;charset=utf-8",
                  }),
                  `${filename}.csv`,
                )
              }
              className="absolute right-0 top-3 inline-flex items-center gap-1 text-sm font-medium text-brand-dark hover:underline"
              aria-label={`Ladda ned tabelldata som CSV: ${indicator.title}`}
            >
              <Download className="size-4" aria-hidden />
              <span className="hidden sm:inline">Ladda ned </span>CSV
            </button>
            <details>
              <summary className="cursor-pointer pr-36 text-sm font-medium text-brand-dark">
                Visa värden som tabell
              </summary>
              <div className="mt-3 max-h-80 overflow-auto">
                <table className="w-full text-left text-sm">
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
                    {tableRows.map((r) => (
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
          </div>
        </figure>
      )}
      <div className="mt-5 flex flex-wrap justify-between gap-2 border-t border-border pt-3 text-sm text-ink-muted">
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
