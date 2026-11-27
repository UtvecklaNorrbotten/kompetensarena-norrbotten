import { educationAxis } from "@/lib/education-axis";
import { EducationTimeline } from "./EducationTimeline";
import { EducationLegend } from "./EducationLegend";
import { EducationHistoryPreview } from "./EducationHistoryPreview";
import { educationGenderColor } from "@/lib/education-colors";
import { useLegendClick } from "@/lib/legend-click";
import { Download } from "@/components/icons";
import { educationCsv, downloadBlob, exportFilename, wrapChartLabel } from "@/lib/education-export";
import { useId, useMemo, useState, type ReactNode } from "react";
import { Visualization } from "@/components/charts/Visualization";
import { observation, periodRange, type VisualizationExport } from "@/lib/visualization-export";
import { useQuery } from "@tanstack/react-query";
import { getUkaEducationSlice } from "@/lib/aggregates.functions";
import { readAllUkaPages, toUkaRows } from "@/lib/uka-education";
import { flushSync } from "react-dom";
import {
  Bar,
  BarChart,
  CartesianGrid,
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
  dimensions,
  formatUkaValue as format,
  periodLabel,
  periodOrder,
  selectUkaRows,
  ukaDetailPeriods,
  ukaGenderSeries,
  ukaRankCategories,
  ukaTarget,
  type UkaCatalogEntry,
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
  onSelect?: (group: string, x: number, y: number) => void;
}) {
  const lines = wrapChartLabel(String(payload?.value ?? ""), 26);
  return (
    <g
      transform={`translate(${x},${y})`}
      role="button"
      tabIndex={0}
      aria-label={`${payload?.value ?? "Grupp"}: klicka för att se historik`}
      style={{ cursor: "pointer" }}
      onClick={(event) => {
        event.stopPropagation();
        onSelect?.(String(payload?.value ?? ""), event.clientX, event.clientY);
      }}
      onKeyDown={(event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          event.stopPropagation();
          const bounds = event.currentTarget.getBoundingClientRect();
          onSelect?.(String(payload?.value ?? ""), bounds.right, bounds.top);
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

/** Hämta exakt den uppdelning och det urval en figur visar, i begränsade sidor. */
function useUkaSlice(
  university: string,
  indicatorId: string,
  target: ReturnType<typeof ukaTarget>,
  enabled = true,
) {
  const breakdown = target.breakdown;
  const selection = Object.fromEntries(
    Object.entries(target.selection).sort(([a], [b]) => a.localeCompare(b)),
  );
  return useQuery({
    queryKey: ["uka-education-slice", university, indicatorId, breakdown ?? null, selection],
    enabled: enabled && breakdown !== undefined,
    staleTime: 5 * 60 * 1000,
    queryFn: async (): Promise<UkaRow[]> =>
      toUkaRows(
        indicatorId,
        university,
        breakdown!,
        await readAllUkaPages((offset) =>
          getUkaEducationSlice({
            data: { university, indicatorId, breakdown: breakdown!, selection, offset },
          }),
        ),
      ),
  });
}

export function EducationFigure({
  indicator,
  catalog,
  filters,
  university,
  fetched,
  fullscreenFilters,
  catalogLoading,
}: {
  indicator: EducationIndicator;
  catalog: UkaCatalogEntry;
  filters: UkaFilters;
  university: string;
  fetched: string | null;
  fullscreenFilters?: ReactNode;
  catalogLoading?: boolean;
}) {
  const [detail, setDetail] = useState(false);
  const [hiddenGenders, setHiddenGenders] = useState<string[]>([]);
  const [showAll, setShowAll] = useState(false);
  const [detailYear, setDetailYear] = useState("");
  const [detailTerm, setDetailTerm] = useState("HT");
  const [historySelection, setHistorySelection] = useState<{
    category: string;
    context: string;
    x: number;
    y: number;
  } | null>(null);
  const switchId = useId();
  const [hiddenOverview, setHiddenOverview] = useState<string[]>([]);
  const overviewTarget = useMemo(() => ukaTarget(catalog, filters), [catalog, filters]);
  const detailTarget = useMemo(() => ukaTarget(catalog, filters, true), [catalog, filters]);
  const overviewQuery = useUkaSlice(university, indicator.id, overviewTarget);
  const detailQuery = useUkaSlice(university, indicator.id, detailTarget, detail);
  const activeQuery = detail ? detailQuery : overviewQuery;
  const sliceLoading =
    catalogLoading ||
    (overviewQuery.isPending && overviewQuery.fetchStatus !== "idle") ||
    (detail && detailQuery.isPending && detailQuery.fetchStatus !== "idle");
  const sliceError = overviewQuery.isError || (detail && detailQuery.isError);
  const overview = useMemo(
    () => selectUkaRows(overviewQuery.data ?? [], filters, false, catalog),
    [overviewQuery.data, filters, catalog],
  );
  const detailSelected = useMemo(
    () => selectUkaRows(detailQuery.data ?? [], filters, true, catalog),
    [detailQuery.data, filters, catalog],
  );
  const selected = detail ? detailSelected : overview;
  const historyContext = JSON.stringify([
    indicator.id,
    university,
    selected.breakdown,
    filters.dimensions,
  ]);
  const historyCategory =
    historySelection?.context === historyContext ? historySelection.category : null;
  const historyRows = selected.rows.filter(
    (row) =>
      row.category === historyCategory &&
      (!/^(HT|VT)/.test(row.period) || row.period.startsWith(detailTerm)),
  );
  function openHistory(category: string, x: number, y: number) {
    setHistorySelection({ category, context: historyContext, x, y });
  }
  const series = ukaGenderSeries(selected.rows);
  const clickLegend = useLegendClick(series, hiddenGenders, setHiddenGenders);
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
  const groupNames = ukaRankCategories(detailSelection.rows);
  const visibleGroups = new Set(showAll ? groupNames : groupNames.slice(0, 5));
  const allBars = [...barRows.values()].sort(
    (a, b) =>
      groupNames.indexOf(String(a["rawCategory"])) - groupNames.indexOf(String(b["rawCategory"])) ||
      periodOrder(String(a["period"])) - periodOrder(String(b["period"])),
  );
  const bars = allBars.filter((r) => visibleGroups.has(String(r["rawCategory"])));
  const selectedFilters = Object.entries(filters.dimensions).filter(([, v]) => v);
  const ignored = selectedFilters.filter(([key]) => !selected.applied.includes(key));
  const hasValues = (
    detail ? detailSelection.rows.filter((r) => series.includes(r.gender)) : genderRows
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
  const axis = educationAxis(
    detailSelection.rows
      .filter((r) => visibleGroups.has(r.category) && series.includes(r.gender))
      .map((r) => r.value)
      .filter((v): v is number => v !== null),
    indicator.unit,
  );
  const domain: [number, number] = [axis.minimum, axis.maximum];

  const tableRows = detail
    ? detailSelection.rows
        .filter((r) => visibleGroups.has(r.category))
        .sort(
          (a, b) =>
            groupNames.indexOf(a.category) - groupNames.indexOf(b.category) ||
            series.indexOf(a.gender) - series.indexOf(b.gender),
        )
    : selected.rows;
  const filename =
    exportFilename(indicator.id, university) + (detail ? "-fordjupning" : "-oversikt");
  const rowHeight = Math.max(
    useGenders ? 90 : 48,
    ...bars.map((r) => wrapChartLabel(String(r["category"]), 26).length * 18 + 20),
  );
  const hidden = detail ? hiddenGenders : hiddenOverview;
  const legend = series
    .filter((gender) => !hidden.includes(detail ? gender : `s0-${gender}`))
    .map((gender) => ({
      label: gender === "Total" ? "Samtliga" : gender,
      color: educationGenderColor(gender),
      dashed: !detail && gender === "Män",
      gender,
    }));
  const exportRows = tableRows.filter((r) => legend.some((item) => item.gender === r.gender));
  const dimensionKeys = selected.breakdown ? selected.breakdown.split("|") : [];
  const periods = [...new Set(exportRows.map((r) => r.period))]
    .sort((a, b) => periodOrder(a) - periodOrder(b))
    .map(periodLabel);
  const sourceUrl = `https://statistik-www.uka.se/export/?indicator=${indicator.ukaId}`;
  const exportData: VisualizationExport = {
    title: indicator.title,
    subtitle: indicator.explanation,
    filename: detail
      ? `${filename}-${detailSelection.year}${detailSelection.semester ? `-${detailTerm.toLowerCase()}` : ""}`
      : filename,
    definition: indicator.definition,
    source: {
      producer: "Universitetskanslersämbetet (UKÄ)",
      product: "Högskolan i siffror",
      identifier: String(indicator.ukaId),
      url: sourceUrl,
      retrieved: fetched,
    },
    period: periodRange(periods),
    unit: indicator.unit,
    anchor: indicator.id,
    filters: {
      Lärosäte: university,
      Kön: legend.map(({ label }) => label).join(", ") || "Alla serier dolda",
      ...Object.fromEntries(
        selectedFilters
          .filter(([key]) => selected.applied.includes(key))
          .map(([key, value]) => [dimensionLabels[key] ?? key, value]),
      ),
      Visning: detail
        ? !showAll && groupNames.length > 5
          ? "Fördjupning, topp 5"
          : "Fördjupning, alla grupper"
        : "Översikt",
    },
    notes: [
      ...(!useGenders ? ["UKÄ saknar könsuppdelning i detta urval."] : []),
      ...(ignored.length
        ? [
            `Uppdelning saknas för: ${ignored.map(([key]) => dimensionLabels[key] ?? key).join(", ")}.`,
          ]
        : []),
      "Tomma källvärden redovisas som Uppgift saknas när källuttaget saknar särskild statuskod.",
    ],
    legend,
    columns: [
      "Lärosäte",
      "Period",
      "Kön",
      ...dimensionKeys.map((key) => dimensionLabels[key] ?? key),
      "Värde",
      "Status",
    ],
    rows: [...exportRows]
      .sort((a, b) => (detail ? 0 : periodOrder(a.period) - periodOrder(b.period)))
      .map((r) => [
        r.university,
        periodLabel(r.period),
        r.gender === "Total" ? "Samtliga" : r.gender,
        ...dimensionKeys.map((key) => dimensions(r)[key] || "Samtliga"),
        ...observation(r.value),
      ]),
  };

  return (
    <Visualization
      id={indicator.id}
      data={exportData}
      exportReady={!sliceLoading && !sliceError && hasValues && legend.length > 0}
      fullscreenFilters={fullscreenFilters}
      className="rounded-xl border border-border bg-surface p-5 md:p-7"
    >
      <div className="flex flex-wrap items-start justify-between gap-4 pr-12">
        <div className="min-w-0 flex-1 basis-60">
          <h3 className="text-xl md:text-2xl">
            <ExplainedTerm term={indicator.title} explanation={indicator.definition} />
          </h3>
          <p className="mt-3 max-w-2xl text-base leading-relaxed text-ink">
            {indicator.explanation}
          </p>
        </div>
        <div className="flex shrink-0 flex-col items-end gap-4">
          <div className="flex shrink-0 items-center gap-2 text-sm">
            <span className={!detail ? "font-semibold text-brand-dark" : "text-ink-muted"}>
              Översikt
            </span>
            <Switch
              id={switchId}
              checked={detail}
              onCheckedChange={(value) => {
                setHiddenOverview([]);
                setDetail(value);
              }}
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
      {detail && (
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
                onChange={(e) => {
                  setDetailTerm(e.target.value);
                  setShowAll(false);
                }}
                className="mt-1 block rounded-md border border-border bg-surface p-2 text-base"
              >
                <option value="HT">HT</option>
                <option value="VT">VT</option>
              </select>
            </label>
          )}
          <p className="basis-full text-sm text-ink-muted">
            {detailSelection.semester
              ? "Förvalt visas höstterminen i det senaste året med tillgängliga HT-data."
              : "Perioderna följer källans indelning."}
          </p>
        </div>
      )}
      {sliceError ? (
        <div className="mt-5 rounded-lg bg-neutral-surface p-6 text-sm" role="alert">
          UKÄ-data kunde inte läsas. Inga exempelvärden visas.{" "}
          <button
            type="button"
            className="text-brand-dark underline"
            onClick={() => {
              void overviewQuery.refetch();
              if (detail) void activeQuery.refetch();
            }}
          >
            Försök igen
          </button>
        </div>
      ) : sliceLoading ? (
        <div className="mt-5 rounded-lg bg-neutral-surface p-6 text-sm" role="status">
          Hämtar UKÄ-data…
        </div>
      ) : !hasValues ? (
        <div className="mt-5 rounded-lg bg-neutral-surface p-6 text-sm" role="status">
          {overview.ambiguous && !detail
            ? "Urvalet omfattar flera överlappande grupper. Precisera urvalet i sidans filter eller välj fördjupning för att se grupperna separat."
            : "Inga publicerade värden finns för detta urval. Ändra år, termin eller sidans filter för att se ett annat urval."}
        </div>
      ) : (
        <figure className="mt-6" aria-label={`${indicator.title}, ${university}`}>
          {detail ? (
            <>
              <h4 className="mb-1 text-lg font-semibold">
                {showAll ? "Alla grupper" : `Topp ${Math.min(5, groupNames.length)}`}
              </h4>
              <p className="mb-4 text-sm text-ink-muted">
                {groupAxisLabel} · {periodText}
              </p>
              <EducationLegend
                items={series.map((gender) => ({
                  key: gender,
                  gender,
                  label: gender === "Total" ? "Samtliga" : gender,
                  lineStyle: gender === "Män" ? "dashed" : "solid",
                }))}
                hidden={hiddenGenders}
                onClick={clickLegend}
              />
              <div className="overflow-x-auto">
                <div
                  data-visualization-export
                  className="min-w-[620px]"
                  style={{ height: Math.max(260, bars.length * rowHeight + 80) }}
                >
                  <ResponsiveContainer width="100%" height="100%">
                    <BarChart
                      accessibilityLayer
                      data={bars}
                      layout="vertical"
                      onClick={(state, event) => {
                        const target = event.target;
                        if (target instanceof Element && target.closest(".recharts-legend-wrapper"))
                          return;
                        const category = state?.activePayload?.[0]?.payload?.rawCategory;
                        if (typeof category === "string")
                          openHistory(category, event.clientX, event.clientY);
                      }}
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
                        ticks={axis.ticks}
                        interval={0}
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
                            onSelect={(group, x, y) => {
                              const row = selected.rows.find(
                                (r) => (r.category.replaceAll("|", " · ") || "Samtliga") === group,
                              );
                              if (row) openHistory(row.category, x, y);
                            }}
                          />
                        }
                        interval={0}
                      />
                      <Tooltip
                        key={`${detailSelection.year}|${detailTerm}`}
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
                      {series.map((gender) => (
                        <Bar
                          key={gender}
                          name={gender === "Total" ? "Samtliga" : gender}
                          dataKey={gender}
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
              {groupNames.length > 5 && (
                <div className="mt-5 flex items-center gap-4">
                  <span aria-hidden className="h-px flex-1 bg-border" />
                  <button
                    type="button"
                    onClick={(event) => {
                      if (!showAll) {
                        setShowAll(true);
                        return;
                      }
                      // Behåll knappens läge i vyn när den långa listan krymper.
                      const button = event.currentTarget;
                      const topBefore = button.getBoundingClientRect().top;
                      flushSync(() => setShowAll(false));
                      const delta = button.getBoundingClientRect().top - topBefore;
                      window.scrollBy({ top: delta, behavior: "instant" });
                    }}
                    className="shrink-0 px-2 py-1 text-sm font-medium text-brand-dark hover:underline"
                  >
                    {showAll ? "Visa topp 5" : `Visa alla ${groupNames.length} grupper`}
                  </button>
                  <span aria-hidden className="h-px flex-1 bg-border" />
                </div>
              )}
            </>
          ) : (
            <div>
              <EducationTimeline
                rows={selected.rows}
                unit={indicator.unit}
                valueAxisLabel={valueAxisLabel}
                visibility={{ hidden: hiddenOverview, setHidden: setHiddenOverview }}
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
                  `${filename}${detail ? "-" + detailSelection.year + "-" + detailTerm : ""}.csv`,
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
      {detail && historyCategory !== null && historySelection && historyRows.length > 0 && (
        <EducationHistoryPreview
          key={`${historyContext}|${historyCategory}|${detailTerm}|${detailSelection.year}`}
          rows={historyRows}
          category={historyCategory}
          unit={indicator.unit}
          x={historySelection.x}
          y={historySelection.y}
          onClose={() => setHistorySelection(null)}
        />
      )}
      <div className="mt-5 flex flex-wrap justify-between gap-2 border-t border-border pt-3 text-sm text-ink-muted">
        <a href={sourceUrl} target="_blank" rel="noreferrer" className="text-brand-dark underline">
          Källa: UKÄ · Högskolan i siffror
        </a>
        {fetched && <span>Senast hämtad: {fetched.slice(0, 10)}</span>}
      </div>
    </Visualization>
  );
}
