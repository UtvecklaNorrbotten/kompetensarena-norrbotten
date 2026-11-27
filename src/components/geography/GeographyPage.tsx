import { countAxis } from "@/lib/education-axis";
import { GeographyFlow } from "./GeographyFlow";
import { useEffect, useState, type ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { useNavigate, useSearch } from "@tanstack/react-router";
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  ReferenceLine,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { PageHeader } from "@/components/ui/PageHeader";
import { Section } from "@/components/layout/Section";
import { DEFAULT_GEO_CODE } from "@/config/geo";
import catalog from "@/data/rmi/catalog.json";
import { getRmiRows, getRmiComparison } from "@/lib/aggregates.functions";
import { flowPairs, rmiNumber, selectRmi, type RmiRow } from "@/lib/rmi";
import { MunicipalityMap } from "./MunicipalityMap";
import { Visualization } from "@/components/charts/Visualization";
import {
  exportFilename,
  observation,
  periodRange,
  type VisualizationExport,
} from "@/lib/visualization-export";

const selectClass =
  "mt-2 w-full rounded-md border border-border bg-surface py-2 pl-3 pr-8 text-base";
const regions: Record<string, string> = catalog.regions;
const groups: Record<string, string> = catalog.groups;
const source =
  "https://www.statistikdatabasen.scb.se/pxweb/sv/ssd/START__AM__AM9906__AM9906B/RegionInd19U3CKM/";
function Figure({
  id,
  title,
  intro,
  children,
  exportData,
  fullscreenFilters,
  exportReady,
}: {
  id: string;
  title: string;
  intro: string;
  children: ReactNode;
  exportData: VisualizationExport;
  fullscreenFilters: ReactNode;
  exportReady: boolean;
}) {
  return (
    <Visualization
      id={id}
      data={exportData}
      exportReady={exportReady}
      fullscreenFilters={fullscreenFilters}
      className="scroll-mt-28 rounded-xl border border-border bg-surface p-5 md:p-7"
    >
      <h2 id={`${id}-title`} className="pr-12 text-2xl">
        {title}
      </h2>
      <p className="mt-3 max-w-3xl text-base leading-relaxed text-ink-muted">{intro}</p>
      <div className="mt-7">{children}</div>
      <p className="mt-6 border-t border-border pt-4 text-sm text-ink-muted">
        <a href={source} target="_blank" rel="noreferrer" className="underline underline-offset-4">
          Källa: SCB, regionala matchningsindikatorer · U3
        </a>
        . Uppdaterad {catalog.updated.slice(0, 10)}. Antal personer, 18–69 år.
      </p>
    </Visualization>
  );
}
function download(rows: RmiRow[], name: string) {
  const header = [
    "Utbildningsgrupp",
    "Kön",
    "Årsintervall",
    "Befolkning år 1",
    "Befolkning år 2",
    "Nettoförändring",
    "Åldersinträden",
    "Åldersutträden",
    "Inflyttade",
    "Utflyttade inklusive avlidna",
    "Till gruppen genom utbildning",
    "Från gruppen genom vidareutbildning",
  ];
  const escape = (value: unknown) => `"${String(value ?? "").replaceAll('"', '""')}"`;
  const csv = [
    header,
    ...rows.map((r) => [
      groups[r[0]],
      r[1] === "2" ? "Kvinnor" : r[1] === "1" ? "Män" : "Totalt",
      ...r.slice(2),
    ]),
  ]
    .map((r) => r.map(escape).join(";"))
    .join("\r\n");
  const url = URL.createObjectURL(new Blob(["\uFEFF" + csv], { type: "text/csv;charset=utf-8;" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = `utbildningsfloden-${name}.csv`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
export function GeographyPage({ initialSection = "" }: { initialSection?: string }) {
  const search = useSearch({ strict: false }) as { geo?: string };
  const navigate = useNavigate();
  const geo = search.geo && regions[search.geo] ? search.geo : DEFAULT_GEO_CODE;
  const [group, setGroup] = useState("00S");
  const [sex, setSex] = useState<"totalt" | "1" | "2">("totalt");
  const [period, setPeriod] = useState(catalog.periods.at(-1)!);
  const [showAll, setShowAll] = useState(false);
  const [series, setSeries] = useState<"population" | "net">("population");
  const [showTable, setShowTable] = useState(false);
  const query = useQuery({
    queryKey: ["rmi-rows", geo, sex],
    queryFn: () => getRmiRows({ data: { geo, sex } }),
    staleTime: 60 * 60 * 1000,
  });
  const comparison = useQuery({
    queryKey: ["rmi-comparison", group, sex, period],
    queryFn: () => getRmiComparison({ data: { group, sex, period } }),
    staleTime: 60 * 60 * 1000,
  });
  const history = selectRmi(query.data ?? [], group, sex);
  const axis = countAxis(
    history.map((r) => r[series === "population" ? 4 : 5]).filter((v): v is number => v !== null),
  );
  const row = history.find((r) => r[2] === period);
  const changeGeo = (value: string) =>
    void navigate({
      to: ".",
      search: (previous: Record<string, unknown>) => ({ ...previous, geo: value }),
      replace: true,
    });
  useEffect(() => {
    const id = window.location.hash.slice(1) || initialSection;
    const frame = requestAnimationFrame(() =>
      document.getElementById(id)?.scrollIntoView({ block: "start" }),
    );
    return () => cancelAnimationFrame(frame);
  }, [initialSection]);
  const municipalityRows = (comparison.data ?? [])
    .filter((r) => r.geo !== "25")
    .sort((a, b) => (b.row?.[4] ?? -Infinity) - (a.row?.[4] ?? -Infinity));
  const visibleRows = showAll ? municipalityRows : municipalityRows.slice(0, 5);
  const compareMax = Math.max(1, ...municipalityRows.map((r) => r.row?.[4] ?? 0));
  const chosenName = regions[geo];
  const groupName = groups[group];

  const sexName = sex === "totalt" ? "Totalt" : sex === "2" ? "Kvinnor" : "Män";
  const flowTitle = "Vad fyller på och vad minskar utbildningsgruppen?";
  const historyTitle = "Hur har utbildningsgruppen förändrats?";
  const historyMeasure =
    series === "population" ? "Antal personer vid intervallets slut" : "SCB:s nettoförändring";
  const common = {
    source: {
      producer: "Statistiska centralbyrån (SCB)",
      product: "Regionala matchningsindikatorer",
      identifier: `U3 · ${catalog.table}`,
      url: source,
      retrieved: catalog.fetched,
    },
    unit: "personer",
    filters: { Geografi: chosenName!, Utbildningsgrupp: groupName!, Kön: sexName },
  };
  const dimensions = (r: RmiRow) => [geo, chosenName!, r[0], groupName!, r[1], sexName, r[2]];
  const dimensionColumns = [
    "Geografikod",
    "Geografi",
    "Utbildningsgruppskod",
    "Utbildningsgrupp",
    "Könskod",
    "Kön",
    "Årsintervall",
  ];
  const flowValues: [string, number | null][] = row
    ? [
        ["Personer vid intervallets början", row[3]],
        ["Personer vid intervallets slut", row[4]],
        ["SCB:s nettoförändring", row[5]],
        ...flowPairs.flatMap<[string, number | null]>((pair) => [
          [pair.inLabel, row[pair.incoming]],
          [pair.outLabel, row[pair.outgoing]],
        ]),
      ]
    : [];
  const flowData: VisualizationExport = {
    ...common,
    title: flowTitle,
    subtitle: "Jämför olika vägar in i och ut ur gruppen mellan två år.",
    indicator: "Utbildningsflöden",
    filename: exportFilename(
      "utbildningsfloden",
      `${chosenName}-${groupName}-${sexName}-${period}`,
    ),
    definition:
      "Förändring av antalet invånare 18–69 år i en utbildningsgrupp mellan två år, efter flyttningar, åldersförändring och ny utbildning.",
    period,
    anchor: "utbildningsfloden",
    notes: [
      "Flödena överlappar. SCB publicerar nettoförändringen som ett separat mått. Utflyttade omfattar även avlidna. Figuren visar utflöden som positiva tal. SCB redovisar dem med minustecken.",
      "SCB skyddar uppgifterna med Cell Key Method (CKM). De publicerade delarna behöver därför inte summera till totalen.",
      ...(period === "2023-2024"
        ? [
            "För 2023–2024 saknas vissa utbildningsflöden efter att SCB ändrat klassificeringen av utbildning.",
          ]
        : []),
    ],
    columns: [...dimensionColumns, "Mått", "Värde", "Status"],
    rows: row
      ? flowValues.map(([measure, value]) => [...dimensions(row), measure, ...observation(value)])
      : [],
  };
  const historyData: VisualizationExport = {
    ...common,
    title: historyTitle,
    indicator: historyMeasure,
    filename: exportFilename(historyMeasure, `${chosenName}-${groupName}-${sexName}`),
    filters: { ...common.filters, Mått: historyMeasure },
    definition:
      "Uppgifter för invånare 18–69 år i den valda utbildningsgruppen. Nettoförändringen publiceras separat av SCB.",
    period: periodRange(history.map((r) => r[2])),
    anchor: "befolkningsutveckling",
    notes: [
      "Antal personer avser årsintervallets sista år. SCB skyddar uppgifterna med Cell Key Method (CKM).",
    ],
    columns: [...dimensionColumns, "Värde", "Status"],
    rows: history.map((r) => [
      ...dimensions(r),
      ...observation(r[series === "population" ? 4 : 5]),
    ]),
  };
  const rankingTitle = "Var finns de utbildade?";
  const rankingData: VisualizationExport = {
    ...common,
    title: rankingTitle,
    subtitle: "Antal personer i utbildningsgruppen vid årsintervallets slut.",
    indicator: "Befolkning efter utbildningsgrupp",
    filename: exportFilename("utbildade-norrbottens-kommuner", `${groupName}-${sexName}-${period}`),
    period,
    anchor: "kommunjamforelse",
    definition: "Antal invånare 18–69 år med en registrerad utbildning i vald utbildningsgrupp.",
    filters: {
      ...common.filters,
      Geografi: "Norrbottens kommuner",
      Visning: showAll ? "Alla 14 kommuner" : "Topp 5 kommuner",
    },
    notes: [
      "Större kommuner har ofta fler personer. SCB skyddar uppgifterna med Cell Key Method (CKM).",
    ],
    columns: [...dimensionColumns, "Värde", "Status"],
    rows: visibleRows.map(({ geo: code, row: item }) => [
      code,
      regions[code]!,
      group,
      groupName!,
      sex,
      sexName,
      period,
      ...observation(item?.[4]),
    ]),
  };
  function renderFilters(withMap = false, withPeriod = false) {
    return (
      <>
        <label className="mt-5 block text-sm font-medium">
          Län eller kommun
          <select className={selectClass} value={geo} onChange={(e) => changeGeo(e.target.value)}>
            {Object.entries(regions).map(([code, name]) => (
              <option value={code} key={code}>
                {name}
              </option>
            ))}
          </select>
        </label>
        {withMap && <MunicipalityMap geo={geo} onGeo={changeGeo} />}
        <label className="mt-6 block text-sm font-medium">
          Utbildningsgrupp
          <select className={selectClass} value={group} onChange={(e) => setGroup(e.target.value)}>
            {Object.entries(groups).map(([code, name]) => (
              <option key={code} value={code}>
                {name}
              </option>
            ))}
          </select>
        </label>
        <label className="mt-5 block text-sm font-medium">
          Kön
          <select
            className={selectClass}
            value={sex}
            onChange={(e) => setSex(e.target.value as typeof sex)}
          >
            <option value="totalt">Totalt</option>
            <option value="2">Kvinnor</option>
            <option value="1">Män</option>
          </select>
        </label>
        {withPeriod && (
          <label className="mt-5 block text-sm font-medium">
            Årsintervall
            <select
              className={selectClass}
              value={period}
              onChange={(e) => setPeriod(e.target.value)}
            >
              {[...catalog.periods].reverse().map((p) => (
                <option key={p}>{p}</option>
              ))}
            </select>
          </label>
        )}
      </>
    );
  }
  const queryStatus = query.isError ? (
    <div role="alert" className="rounded-xl border border-border p-6">
      Statistiken kunde inte hämtas.{" "}
      <button type="button" className="underline" onClick={() => query.refetch()}>
        Försök igen
      </button>
    </div>
  ) : query.isPending ? (
    <div role="status" className="min-h-96 animate-pulse rounded-xl bg-neutral-surface p-6">
      Hämtar SCB-statistik…
    </div>
  ) : null;

  return (
    <div className="font-normal">
      <Section tone="light" className="py-9 md:py-12">
        <PageHeader
          eyebrow="Län och kommun · SCB"
          title="Kompetensförsörjning där du bor"
          intro="Utforska hur antalet personer med olika utbildningar förändras i Norrbotten. Se vad flyttningar, nya utbildningar och åldersförändringar betyder för länet och kommunerna."
        />
        <nav
          aria-label="Sidans avsnitt"
          className="mt-6 flex flex-wrap gap-x-6 gap-y-3 text-base text-brand-dark"
        >
          <a href="#utbildningsfloden" className="underline underline-offset-4">
            Flöden in och ut
          </a>
          <a href="#befolkningsutveckling" className="underline underline-offset-4">
            Utveckling över tid
          </a>
          <a href="#kommunjamforelse" className="underline underline-offset-4">
            Jämför kommunerna
          </a>
        </nav>
      </Section>
      <div className="mx-auto grid max-w-(--container-content) items-start gap-6 px-4 py-8 md:px-8 lg:grid-cols-[280px_minmax(0,1fr)] lg:gap-8">
        <aside
          aria-label="Filter för län och kommun"
          className="rounded-xl border border-border bg-surface p-5 lg:sticky lg:top-24 lg:max-h-[calc(100vh-112px)] lg:overflow-y-auto"
        >
          <h2 className="text-lg">Filtrera sidan</h2>
          <p className="mt-2 text-sm leading-relaxed text-ink-muted">
            Dina val gäller alla figurer. Kommunjämförelsen visar alltid länets 14 kommuner.
          </p>
          {renderFilters(true, true)}
          <button
            type="button"
            className="mt-6 text-sm text-brand-dark underline underline-offset-4"
            onClick={() => {
              changeGeo(DEFAULT_GEO_CODE);
              setGroup("00S");
              setSex("totalt");
              setPeriod(catalog.periods.at(-1)!);
            }}
          >
            Återställ urval
          </button>
        </aside>
        <div className="min-w-0 space-y-10 md:space-y-14">
          <div aria-live="polite" className="rounded-xl border border-border bg-surface p-5">
            <h2 className="text-xl">{chosenName}</h2>
            <p className="mt-2 text-base leading-relaxed">
              {groupName} · {sex === "totalt" ? "Totalt" : sex === "2" ? "Kvinnor" : "Män"} ·{" "}
              {period}
            </p>
            <p className="mt-3 text-base leading-relaxed text-ink-muted">
              Uppgifterna gäller personer som bor i området, oavsett var de arbetar eller studerar.
              En utbildningsgrupp beskriver personernas registrerade utbildning, inte vilken
              utbildning de går just nu.
            </p>
          </div>
          <Figure
            id="utbildningsfloden"
            title={flowTitle}
            exportData={flowData}
            exportReady={!queryStatus && !!row}
            fullscreenFilters={
              <div className="grid gap-x-4 sm:grid-cols-2 lg:grid-cols-4">
                {renderFilters(false, true)}
              </div>
            }
            intro="Jämför olika vägar in i och ut ur gruppen. Figurerna visar förändringar mellan två år, inte övergångar mellan enskilda utbildningsprogram."
          >
            {queryStatus ??
              (!row ? (
                <p>Inga publicerade värden finns för urvalet.</p>
              ) : (
                <>
                  {period === "2023-2024" && (
                    <p className="mb-7 rounded-lg bg-brand-light p-4 text-base leading-relaxed">
                      För 2023–2024 saknas vissa uppgifter om nya utbildningar. SCB har ändrat hur
                      utbildning klassificeras. Saknade värden betyder inte att flödet är noll. Välj
                      ett tidigare årsintervall för att se fler utbildningsflöden.
                    </p>
                  )}
                  <GeographyFlow row={row} />
                </>
              ))}
          </Figure>
          <Figure
            id="befolkningsutveckling"
            title={historyTitle}
            exportData={historyData}
            exportReady={
              !queryStatus && history.some((r) => r[series === "population" ? 4 : 5] !== null)
            }
            fullscreenFilters={
              <div className="grid gap-x-4 sm:grid-cols-2 lg:grid-cols-3">{renderFilters()}</div>
            }
            intro="Följ antalet personer eller SCB:s nettoförändring mellan år. Historiken visar alla tillgängliga årsintervall för ditt urval."
          >
            {queryStatus ?? (
              <>
                <div
                  className="mb-5 flex flex-wrap gap-2"
                  role="group"
                  aria-label="Välj mått i historiken"
                >
                  {[
                    ["population", "Antal personer"],
                    ["net", "Nettoförändring"],
                  ].map(([value, label]) => (
                    <button
                      key={value}
                      type="button"
                      aria-pressed={series === value}
                      className={`rounded-md border px-4 py-2 text-sm ${series === value ? "border-brand bg-brand-light" : "border-border"}`}
                      onClick={() => setSeries(value as typeof series)}
                    >
                      {label}
                    </button>
                  ))}
                </div>
                <div
                  className="h-80"
                  data-visualization-export
                  data-visualization-grow
                  role="img"
                  aria-label={`${series === "population" ? "Antal personer" : "Nettoförändring"} över tid i ${chosenName}. Värden finns också i datatabellen.`}
                >
                  <ResponsiveContainer width="100%" height="100%">
                    <LineChart
                      data={history.map((r) => ({
                        period: r[2],
                        value: r[series === "population" ? 4 : 5],
                      }))}
                      margin={{ left: 10, right: 20, top: 15, bottom: 20 }}
                    >
                      <CartesianGrid vertical={false} stroke="#e3e7df" />
                      <XAxis dataKey="period" tick={{ fontSize: 14 }} interval="preserveStartEnd" />
                      <YAxis
                        domain={[axis.minimum, axis.maximum]}
                        ticks={axis.ticks}
                        interval={0}
                        tick={{ fontSize: 14 }}
                        tickFormatter={(v) => rmiNumber(v)}
                        width={75}
                        allowDecimals={false}
                      />
                      <ReferenceLine y={0} stroke="#667260" strokeWidth={1.5} />
                      <Tooltip
                        formatter={(v) => [
                          rmiNumber(v),
                          series === "population"
                            ? "Antal personer vid intervallets slut"
                            : "Nettoförändring",
                        ]}
                      />
                      <Line
                        type="linear"
                        dataKey="value"
                        stroke="#487629"
                        strokeWidth={3}
                        dot={{ r: 3 }}
                        connectNulls={false}
                        isAnimationActive={false}
                      />
                    </LineChart>
                  </ResponsiveContainer>
                </div>
                <p className="mt-3 text-sm text-ink-muted">
                  Antal personer avser årsintervallets sista år. Netto visas som SCB publicerar det
                  och räknas inte fram från de avrundade delflödena.
                </p>
              </>
            )}
          </Figure>
          <Figure
            id="kommunjamforelse"
            title={rankingTitle}
            exportData={rankingData}
            exportReady={comparison.isSuccess && visibleRows.length > 0}
            fullscreenFilters={
              <div className="grid gap-x-4 sm:grid-cols-2 lg:grid-cols-4">
                {renderFilters(false, true)}
              </div>
            }
            intro="Jämför antalet personer i samma utbildningsgrupp och årsintervall. Större kommuner har ofta fler personer – jämförelsen visar antal, inte andelar eller kompetensbrist."
          >
            {comparison.isPending ? (
              <p role="status">Hämtar kommunjämförelse…</p>
            ) : comparison.isError ? (
              <p role="alert">
                Jämförelsen kunde inte hämtas.{" "}
                <button type="button" className="underline" onClick={() => comparison.refetch()}>
                  Försök igen
                </button>
              </p>
            ) : (
              <>
                <h3 className="mb-5 text-lg">
                  {showAll ? "Alla 14 kommuner" : "Topp 5 kommuner"} · {period.slice(-4)}
                </h3>
                <div className="space-y-4" data-visualization-export>
                  {visibleRows.map((item) => (
                    <div
                      key={item.geo}
                      className={`relative rounded-lg p-3 hover:bg-brand-light ${geo === item.geo ? "bg-brand-light ring-1 ring-brand" : ""}`}
                    >
                      <button
                        type="button"
                        onClick={() => changeGeo(item.geo)}
                        aria-pressed={geo === item.geo}
                        aria-label={`Välj ${regions[item.geo]}, ${rmiNumber(item.row?.[4])}`}
                        className="absolute inset-0 w-full rounded-lg focus-visible:outline"
                        data-export-ignore
                      />
                      <span className="flex justify-between gap-4 text-base">
                        <span>{regions[item.geo]}</span>
                        <span className="tabular-nums">{rmiNumber(item.row?.[4])}</span>
                      </span>
                      <span
                        className="mt-2 block h-2 rounded-sm bg-neutral-surface"
                        aria-hidden="true"
                      >
                        <span
                          className="block h-full rounded-sm bg-[#487629]"
                          style={{
                            width: `${(Math.max(0, item.row?.[4] ?? 0) / compareMax) * 100}%`,
                          }}
                        />
                      </span>
                    </div>
                  ))}
                </div>
                <div className="mt-6 flex items-center gap-4">
                  <span className="h-px flex-1 bg-border" />
                  <button
                    type="button"
                    className="py-2 text-sm text-brand-dark underline underline-offset-4"
                    aria-expanded={showAll}
                    onClick={() => setShowAll(!showAll)}
                  >
                    {showAll ? "Visa topp 5" : "Visa alla 14 kommuner"}
                  </button>
                  <span className="h-px flex-1 bg-border" />
                </div>
              </>
            )}
          </Figure>
          <section className="rounded-xl border border-border bg-surface p-5 md:p-7">
            <h2 className="text-xl">Se värdena och läs om statistiken</h2>
            <div className="mt-5 flex flex-wrap gap-5">
              <button
                type="button"
                aria-expanded={showTable}
                className="text-base text-brand-dark underline underline-offset-4"
                onClick={() => setShowTable(!showTable)}
              >
                {showTable ? "Dölj datatabell" : "Visa datatabell"}
              </button>
              <button
                type="button"
                disabled={!history.length}
                className="text-base text-brand-dark underline underline-offset-4 disabled:opacity-50"
                onClick={() => download(history, geo)}
              >
                Ladda ner urvalet som CSV
              </button>
            </div>
            {showTable && (
              <div className="mt-5 overflow-x-auto">
                <table className="w-full text-left text-sm">
                  <caption className="mb-3 text-left">
                    {chosenName} · {groupName}. Tomma uppgifter visas som Uppgift saknas.
                  </caption>
                  <thead>
                    <tr>
                      {[
                        "Årsintervall",
                        "År 1",
                        "År 2",
                        "Netto",
                        "Åldersinträden",
                        "Åldersutträden",
                        "Inflyttade",
                        "Utflyttade, inkl. avlidna",
                        "Ny utbildning",
                        "Vidareutbildade",
                      ].map((label) => (
                        <th key={label} scope="col" className="border-b border-border p-3">
                          {label}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {history.map((r) => (
                      <tr key={r[2]}>
                        {r.slice(2).map((value, i) =>
                          i === 0 ? (
                            <th
                              scope="row"
                              key={i}
                              className="border-b border-border p-3 font-normal"
                            >
                              {String(value)}
                            </th>
                          ) : (
                            <td key={i} className="border-b border-border p-3 tabular-nums">
                              {rmiNumber(value)}
                            </td>
                          ),
                        )}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
            <details className="mt-6">
              <summary className="cursor-pointer text-base font-semibold">
                Så ska uppgifterna tolkas
              </summary>
              <div className="mt-4 space-y-4 text-base leading-relaxed text-ink-muted">
                <p>
                  Utbildningsflöden handlar om hur sammansättningen av de boende förändras. De visar
                  inte vem som byter från en bestämd utbildningsgrupp till en annan. Därför visas
                  inga påhittade kopplingar mellan grupper.
                </p>
                <p>
                  SCB skyddar uppgifterna med Cell Key Method (CKM), som tillför en liten
                  slumpmässig osäkerhet. Skillnader mellan små grupper bör tolkas försiktigt.
                  Totalen för kvinnor och män hämtas från SCB och summeras inte här.
                </p>
                <p>
                  Länsvärden hämtas separat. Kommunernas flöden summeras inte till länet eftersom
                  flyttningar inom länet då skulle räknas med. U3 redovisas inte för riket.
                </p>
                <p>
                  Åldersinträden och åldersutträden avser gränserna för den valda åldersgruppen,
                  18–69 år. Åldersutträden är inte ett mått på faktiska pensionsavgångar.
                </p>
                <p>
                  ”Till gruppen genom utbildning” är SCB:s mått examinerade. ”Från gruppen genom
                  vidareutbildning” betyder att personen fått en utbildning som placerar den i en
                  annan grupp.
                </p>
              </div>
            </details>
          </section>
        </div>
      </div>
    </div>
  );
}
