import { EducationTimeline } from "./EducationTimeline";
import { educationGenderColor } from "@/lib/education-colors";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
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
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
  type TooltipProps,
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
  ukaDetailPeriods,
  ukaGenderSeries,
  type UkaFilters,
  type UkaRow,
} from "@/lib/uka-view";

function HistoryTooltip({
  active,
  payload,
  unit,
}: TooltipProps<number, string> & { unit: string }) {
  if (!active || !payload?.length) return null;
  const row = payload[0]?.payload;
  return (
    <div className="max-w-72 rounded-lg border border-border bg-surface p-3 text-sm text-ink shadow-md">
      <p className="font-semibold">{row.group}</p>
      <p className="mt-1 text-ink-muted">
        {/^(\d{4})$/.test(String(row.period)) ? "År" : "Period"}: {periodLabel(String(row.period))}
      </p>
      {payload.map((item) => (
        <p key={String(item.dataKey)} className="mt-2 flex items-center gap-2">
          <span
            aria-hidden
            className="inline-block size-3 rounded-sm"
            style={{ background: item.color }}
          />
          {item.name}: {format(item.value, unit)}
        </p>
      ))}
      <p className="mt-3 font-medium text-brand-dark">Klicka för att se historik</p>
    </div>
  );
}

function CategoryTick({
  x = 0,
  y = 0,
  payload,
  onSelect,
}: {
  x?: number;
  y?: number;
  payload?: { value?: string };
  onSelect?: (group: string) => void;
}) {
  const lines = wrapChartLabel(String(payload?.value ?? ""), 26);
  return (
    <g
      transform={`translate(${x},${y})`}
      role="button"
      tabIndex={0}
      aria-label={`${payload?.value ?? "Grupp"}: klicka för att se historik`}
      style={{ cursor: "pointer" }}
      onClick={() => onSelect?.(String(payload?.value ?? ""))}
      onKeyDown={(event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          onSelect?.(String(payload?.value ?? ""));
        }
      }}
    >
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
  const [comparePrograms, setComparePrograms] = useState(false);
  const [chosenPrograms, setChosenPrograms] = useState<string[]>([]);
  const [hiddenGenders, setHiddenGenders] = useState<string[]>([]);
  const [showAll, setShowAll] = useState(false);
  const [detailYear, setDetailYear] = useState("");
  const [detailTerm, setDetailTerm] = useState("all");
  const [historySelection, setHistorySelection] = useState<{
    category: string;
    context: string;
  } | null>(null);
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
  const historyContext = JSON.stringify([
    indicator.id,
    university,
    selected.breakdown,
    filters.dimensions,
  ]);
  const historyCategory =
    historySelection?.context === historyContext ? historySelection.category : null;
  const historyRows = selected.rows.filter((row) => row.category === historyCategory);
  function openHistory(category: string) {
    setHistorySelection({ category, context: historyContext });
  }
  const series = ukaGenderSeries(selected.rows);
  const genderRows = selected.rows.filter((r) => series.includes(r.gender));
  const detailSelection = ukaDetailPeriods(selected.rows, detailYear, detailTerm);
  const periodText = detailSelection.periods.map(periodLabel).join(" och ");
  const latestOverview = overview.rows
    .filter((r) => r.gender === filters.gender)
    .sort((a, b) => periodOrder(a["period"]) - periodOrder(b["period"]))
    .at(-1);
  const useGenders = series.includes("Kvinnor");
  const barRows = new Map<string, Record<string, string | number | null>>();
  for (const r of detailSelection.rows) {
    if (!series.includes(r.gender)) continue;
    const group = r.category.replaceAll("|", " · ") || "Samtliga";
    const key = `${r.category}|${r.period}`;
    const existing = barRows.get(key) ?? {
      category: group,
      group,
      rawCategory: r.category,
      period: r.period,
    };
    existing[r.gender] = r.value;
    barRows.set(key, existing);
  }
  const groupNames = [...new Set([...barRows.values()].map((r) => String(r["group"])))].sort(
    (a, b) => a.localeCompare(b, "sv"),
  );
  const visibleGroups = showAll ? groupNames : groupNames.slice(0, 12);
  const allBars = [...barRows.values()].sort(
    (a, b) =>
      String(a["group"]).localeCompare(String(b["group"]), "sv") ||
      periodOrder(String(a["period"])) - periodOrder(String(b["period"])),
  );
  const bars = allBars.filter((r) => visibleGroups.includes(String(r["group"])));
  const programOptions = [...new Set(selected.rows.map((r) => r.category))].sort((a, b) =>
    a.localeCompare(b, "sv"),
  );
  const comparison = detail && comparePrograms && selected.breakdown === "program";
  const comparisonPrograms = chosenPrograms.filter((p) => programOptions.includes(p));
  const activePrograms = comparisonPrograms.length
    ? comparisonPrograms
    : programOptions.slice(0, 2);
  const comparisonRows = selected.rows.filter((r) => activePrograms.includes(r.category));
  const selectedFilters = Object.entries(filters.dimensions).filter(([, v]) => v);
  const ignored = selectedFilters.filter(([key]) => !selected.applied.includes(key));
  const hasValues = (
    comparison
      ? comparisonRows
      : detail
        ? detailSelection.rows.filter((r) => series.includes(r.gender))
        : genderRows
  ).some((r) => r.value !== null);
  const valueAxisLabel =
    indicator.unit === "%"
      ? "Andel (%)"
      : indicator.unit === "HST"
        ? "Helårsstudenter (HST)"
        : indicator.unit === "antal"
          ? "Antal"
          : "Sökande per antagen";
  const groupAxisLabel = `${
    selected.breakdown
      .split("|")
      .map((key) => dimensionLabels[key] ?? key)
      .filter(Boolean)
      .join(" / ") || "Grupp"
  }`;
  const domain: [number, number | "auto"] = indicator.unit === "%" ? [0, 100] : [0, "auto"];

  const tableRows = comparison ? comparisonRows : detail ? detailSelection.rows : selected.rows;
  const filename =
    exportFilename(indicator.id, university) +
    (comparison ? "-programjamforelse" : detail ? "-fordjupning" : "-oversikt");
  const contextText = `${university} · ${useGenders ? (series.includes("Total") ? "Kvinnor, män och total" : "Kvinnor och män") : "Samtliga"}${selectedFilters
    .filter(([key]) => selected.applied.includes(key))
    .map(([key, value]) => ` · ${dimensionLabels[key] ?? key}: ${value}`)
    .join("")}`;
  const rowHeight = Math.max(
    useGenders ? 90 : 48,
    ...bars.map((r) => wrapChartLabel(String(r["category"]), 26).length * 18 + 20),
  );
  async function saveFigure() {
    const svg = Array.from(
      chartRef.current?.querySelectorAll<SVGSVGElement>("svg.recharts-surface") ?? [],
    );
    if (!svg.length) {
      setSaveError("Figuren har inte laddats färdigt. Försök igen.");
      return;
    }
    setSaving(true);
    setSaveError("");
    try {
      await saveEducationPng(svg, filename, indicator.title, [
        contextText,
        indicator.explanation,
        ...(comparison
          ? [`Program: ${activePrograms.join(", ")}. Samtliga publicerade perioder visas.`]
          : []),
        ...(comparison
          ? [
              ...activePrograms.map((p, i) => `${["Heldragen", "Streckad", "Prickad"][i]}: ${p}.`),
              "Grön: kvinnor. Gul/orange: män. Ljusgrå: samtliga.",
            ]
          : useGenders
            ? [
                `Grön: Kvinnor. Gul/orange: Män (streckad linje i översikt).${series.includes("Total") ? " Ljusgrå: Samtliga." : ""}`,
              ]
            : []),
        `Enhet: ${indicator.unit}. ${detail && !comparison ? `Period: ${periodText}. ${!showAll && groupNames.length > 12 ? "De första 12 grupperna visas." : "Alla grupper visas."}` : "Samtliga tillgängliga perioder visas."}`,
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
      {detail && selected.breakdown === "program" && (
        <div className="mt-5">
          <button
            type="button"
            aria-pressed={comparePrograms}
            onClick={() => setComparePrograms(!comparePrograms)}
            className="rounded-md border border-border px-3 py-2 text-sm font-semibold text-brand-dark"
          >
            {comparePrograms ? "Visa staplar per år" : "Jämför program över tid"}
          </button>
          {comparePrograms && (
            <fieldset className="mt-3">
              <legend className="mb-2 text-sm font-medium">Välj upp till tre program</legend>
              <div className="flex max-h-48 flex-wrap gap-3 overflow-y-auto">
                {programOptions.map((program) => (
                  <label key={program} className="flex items-center gap-2 text-sm">
                    <input
                      type="checkbox"
                      checked={activePrograms.includes(program)}
                      disabled={
                        (!activePrograms.includes(program) && activePrograms.length >= 3) ||
                        (activePrograms.includes(program) && activePrograms.length === 1)
                      }
                      onChange={() => {
                        const next = activePrograms.includes(program)
                          ? activePrograms.filter((p) => p !== program)
                          : [...activePrograms, program];
                        if (next.length) setChosenPrograms(next);
                      }}
                    />
                    {program}
                  </label>
                ))}
              </div>
            </fieldset>
          )}
        </div>
      )}
      {detail && !comparison && (
        <div className="mt-5 flex flex-wrap items-end gap-4">
          <label className="text-sm font-medium">
            {detailSelection.semester ? "År" : "Period"}
            <select
              value={detailSelection.year}
              onChange={(e) => {
                setDetailYear(e.target.value);
                setShowAll(false);
              }}
              className="mt-1 block rounded-md border border-border bg-surface p-2 text-base"
            >
              {detailSelection.years.map((year) => (
                <option key={year} value={year}>
                  {year}
                </option>
              ))}
            </select>
          </label>
          {detailSelection.semester && (
            <label className="text-sm font-medium">
              Termin
              <select
                value={detailTerm}
                onChange={(e) => setDetailTerm(e.target.value)}
                className="mt-1 block rounded-md border border-border bg-surface p-2 text-base"
              >
                <option value="all">HT och VT – separat</option>
                <option value="HT">Hösttermin</option>
                <option value="VT">Vårtermin</option>
              </select>
            </label>
          )}
          <p className="basis-full text-sm text-ink-muted">
            {detailSelection.semester
              ? "Förvalt visas senaste året med data för både HT och VT, om ett sådant finns. Samma person kan förekomma båda terminerna; värdena summeras därför inte."
              : "Perioderna följer källans indelning."}
          </p>
        </div>
      )}
      {!hasValues ? (
        <div className="mt-5 rounded-lg bg-neutral-surface p-6 text-sm" role="status">
          {overview.ambiguous && !detail
            ? "Urvalet omfattar flera överlappande grupper. Precisera urvalet i sidans filter eller välj fördjupning för att se grupperna separat."
            : "Inga publicerade värden finns för detta urval. Ändra år, termin eller sidans filter för att se ett annat urval."}
        </div>
      ) : (
        <figure className="mt-6" aria-label={`${indicator.title}, ${university}`}>
          {comparison ? (
            <div ref={chartRef}>
              <EducationTimeline
                key={activePrograms.join("|")}
                rows={comparisonRows}
                unit={indicator.unit}
                valueAxisLabel={valueAxisLabel}
                programs={activePrograms}
              />
            </div>
          ) : detail ? (
            <>
              <p className="mb-4 text-sm">
                {dimensionLabels[selected.breakdown.split("|").at(-1) ?? ""] ?? "Uppdelning"} ·{" "}
                {periodText}
                {!showAll && groupNames.length > 12 ? " · de första 12 grupperna" : ""}
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
                      style={{ cursor: "pointer" }}
                      margin={{ left: 16, right: 32, top: 16, bottom: 16 }}
                    >
                      <CartesianGrid stroke="var(--border)" horizontal={false} />
                      <XAxis
                        type="number"
                        height={50}
                        label={{
                          value: valueAxisLabel,
                          position: "insideBottom",
                          offset: 0,
                          fill: "var(--ink)",
                          fontSize: 14,
                        }}
                        domain={domain}
                        tick={{ fill: "var(--ink)", fontSize: 14 }}
                      />
                      <YAxis
                        type="category"
                        dataKey="category"
                        allowDuplicatedCategory
                        width={270}
                        label={{
                          value: groupAxisLabel,
                          angle: -90,
                          position: "insideLeft",
                          offset: 0,
                          fill: "var(--ink)",
                          fontSize: 14,
                          style: { textAnchor: "middle" },
                        }}
                        tick={
                          <CategoryTick
                            onSelect={(group) => {
                              const row = selected.rows.find(
                                (r) => (r.category.replaceAll("|", " · ") || "Samtliga") === group,
                              );
                              if (row) openHistory(row.category);
                            }}
                          />
                        }
                        interval={0}
                      />
                      <Tooltip
                        isAnimationActive={false}
                        content={<HistoryTooltip unit={indicator.unit} />}
                        contentStyle={{
                          background: "var(--surface)",
                          maxWidth: 280,
                          whiteSpace: "normal",
                          overflowWrap: "anywhere",
                          border: "1px solid var(--border)",
                          borderRadius: "var(--radius)",
                        }}
                      />
                      <Legend
                        onClick={(item) => {
                          const key = String(item.dataKey);
                          setHiddenGenders((old) =>
                            old.includes(key) ? old.filter((g) => g !== key) : [...old, key],
                          );
                        }}
                        wrapperStyle={{ cursor: "pointer" }}
                      />
                      {series.map((gender) => (
                        <Bar
                          key={gender}
                          name={gender === "Total" ? "Samtliga" : gender}
                          dataKey={gender}
                          onClick={(data) => {
                            const category = data.payload?.rawCategory;
                            if (typeof category === "string") openHistory(category);
                          }}
                          hide={hiddenGenders.includes(gender)}
                          fill={educationGenderColor(gender)}
                          isAnimationActive={false}
                          radius={[0, 3, 3, 0]}
                        />
                      ))}
                    </BarChart>
                  </ResponsiveContainer>
                </div>
              </div>
              {groupNames.length > 12 && (
                <button
                  type="button"
                  onClick={() => setShowAll(!showAll)}
                  className="mt-3 text-sm text-brand-dark underline"
                >
                  {showAll
                    ? "Visa de första 12 grupperna"
                    : `Visa alla ${groupNames.length} grupper`}
                </button>
              )}
            </>
          ) : (
            <div ref={chartRef}>
              <EducationTimeline
                rows={selected.rows}
                unit={indicator.unit}
                valueAxisLabel={valueAxisLabel}
              />
            </div>
          )}
          <div className="relative mt-5 border-t border-border pt-3">
            <button
              type="button"
              onClick={() =>
                downloadBlob(
                  new Blob([educationCsv(tableRows, indicator.title, indicator.unit)], {
                    type: "text/csv;charset=utf-8",
                  }),
                  `${filename}${detail && !comparison ? "-" + detailSelection.year + "-" + detailTerm : ""}.csv`,
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
      <Sheet
        open={historyCategory !== null && historyRows.length > 0}
        onOpenChange={(open) => {
          if (!open) setHistorySelection(null);
        }}
      >
        <SheetContent
          side="right"
          className="overflow-y-auto"
          style={{ width: "min(100vw, 760px)", maxWidth: "none" }}
        >
          <SheetHeader className="pr-8 text-left">
            <SheetTitle>
              Historik – {historyCategory?.replaceAll("|", " · ") || "Samtliga"}
            </SheetTitle>
            <SheetDescription>
              {indicator.title} · {university}
            </SheetDescription>
          </SheetHeader>
          <div className="mt-6">
            <EducationTimeline
              key={`${historyContext}|${historyCategory}`}
              rows={historyRows}
              unit={indicator.unit}
              valueAxisLabel={valueAxisLabel}
            />
          </div>
        </SheetContent>
      </Sheet>
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
