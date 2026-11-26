import { useState, type ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { useNavigate, useSearch } from "@tanstack/react-router";
import { Section } from "@/components/layout/Section";
import { PageHeader } from "@/components/ui/PageHeader";
import { MunicipalityMap } from "@/components/geography/MunicipalityMap";
import { DEFAULT_GEO_CODE } from "@/config/geo";
import catalog from "@/data/matching/catalog.json";
import { getMatchingSlice, getMatchingComparison } from "@/lib/aggregates.functions";
import { matchingMetrics, matchingNumber, matchingValue } from "@/lib/matching";
import {
  MatchingHistory,
  MatchingRanking,
  MatchingTable,
  type MatchingPoint,
} from "./MatchingCharts";

const regions: Record<string, string> = catalog.regions;
const education: Record<string, string> = catalog.education;
const branches: Record<string, string> = catalog.branches;
const groups: Record<string, string[]> = catalog.groups;
const control = "mt-2 w-full rounded-md border border-border bg-surface px-3 py-2 text-base";
function Figure({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="min-w-0 rounded-xl border border-border bg-surface p-5 md:p-7">
      <h2 className="mb-6 text-2xl">{title}</h2>
      {children}
      <p className="mt-6 border-t border-border pt-4 text-sm text-ink-muted">
        <a className="underline" href={catalog.source} target="_blank" rel="noreferrer">
          Källa: SCB, regionala matchningsindikatorer · E3
        </a>
        . Befolkningen 20–69 år, folkbokförda i regionen. Uppdaterad {catalog.updated.slice(0, 10)}.
      </p>
    </section>
  );
}
function BranchFlow({ rows, label }: { rows: MatchingPoint[]; label: string }) {
  const [all, setAll] = useState(false);
  const sorted = [...rows].sort((a, b) => (b.value ?? -Infinity) - (a.value ?? -Infinity));
  const shown = all ? sorted : sorted.slice(0, 5);
  const maximum = Math.max(1, ...rows.map((r) => r.value ?? 0));
  const height = Math.max(270, shown.length * 62);
  return (
    <>
      <p className="mb-5 text-ink-muted">
        {label}. Bandens bredd visar antalet i varje bransch. Branscherna visas var för sig; ingen
        summerad total räknas fram.
      </p>
      <div className="grid grid-cols-[minmax(85px,1fr)_minmax(45px,1fr)_minmax(130px,2fr)] items-center gap-2">
        <div className="rounded-lg bg-brand-light p-3 text-sm">Vald utbildning</div>
        <svg
          viewBox={`0 0 120 ${height}`}
          className="h-full w-full"
          style={{ height }}
          preserveAspectRatio="none"
          aria-hidden="true"
        >
          {shown.map((r, i) =>
            r.value !== null && r.value > 0 ? (
              <path
                key={r.code}
                d={`M0 ${height / 2} C60 ${height / 2},60 ${((i + 0.5) * height) / shown.length},120 ${((i + 0.5) * height) / shown.length}`}
                stroke="var(--chart-1)"
                opacity="0.45"
                strokeWidth={Math.max(1, (r.value / maximum) * 22)}
                fill="none"
              />
            ) : null,
          )}
        </svg>
        <div className="flex h-full flex-col justify-around gap-3">
          {shown.map((r) => (
            <p key={r.code} className="text-sm">
              <span className="block">{r.label}</span>
              <strong>{matchingNumber(r.value, 0)}</strong>
            </p>
          ))}
        </div>
      </div>
      <button
        type="button"
        className="mt-5 underline"
        aria-expanded={all}
        onClick={() => setAll(!all)}
      >
        {all ? "Visa topp 5" : "Visa alla branscher"}
      </button>
      <MatchingTable rows={sorted} unit="personer" name={label} />
    </>
  );
}
export function MatchingPage() {
  const search = useSearch({ strict: false }) as { geo?: string };
  const navigate = useNavigate();
  const geo = search.geo && search.geo in regions ? search.geo : DEFAULT_GEO_CODE;
  const [sex, setSex] = useState<"totalt" | "1" | "2">("totalt");
  const [classification, setClassification] = useState("grupp");
  const [group, setGroup] = useState("00S");
  const [period, setPeriod] = useState(catalog.periods.at(-1)!);
  const [metric, setMetric] = useState(6);
  const [flowMetric, setFlowMetric] = useState(0);
  const [level, setLevel] = useState("kommun");
  const selection = { geo, sex, education: group, period };
  const query = useQuery({
    queryKey: ["matching", selection],
    queryFn: () => getMatchingSlice({ data: selection }),
    staleTime: 3600000,
  });
  const comparison = useQuery({
    queryKey: ["matching-comparison", group, sex, period],
    queryFn: () => getMatchingComparison({ data: { education: group, sex, period } }),
    staleTime: 3600000,
  });
  const changeGeo = (value: string) =>
    void navigate({
      to: ".",
      search: (previous: Record<string, unknown>) => ({ ...previous, geo: value }),
      replace: true,
    });
  const name = regions[geo]!;
  const metricName = matchingMetrics[metric]!.label;
  const unit = matchingMetrics[metric]!.unit;
  const national = new Map(query.data?.national.map((r) => [r[2], matchingValue(r, metric)]));
  const history = (query.data?.history ?? []).map((r) => ({
    code: r[2],
    label: r[2],
    value: matchingValue(r, metric),
    comparison: geo === "00" ? undefined : (national.get(r[2]) ?? null),
  }));
  const ranking = (query.data?.ranking ?? [])
    .filter((r) => groups[classification]!.includes(r[0]) && !r[0].startsWith("00"))
    .map((r) => ({ code: r[0], label: education[r[0]]!, value: matchingValue(r, metric) }));
  const point = query.data?.history.find((r) => r[2] === period);
  const comparisons = (comparison.data ?? []).map((r) => ({
    code: r[0],
    label: regions[r[0]]!,
    value: r[3 + metric] as number | null,
  }));
  const county = geo.length === 4 ? geo.slice(0, 2) : geo === "00" ? "25" : geo;
  const selectedComparison = comparisons.filter((r) =>
    level === "län"
      ? r.code.length === 2 && r.code !== "00"
      : r.code.length === 4 && r.code.startsWith(county),
  );
  const flows = (query.data?.flows ?? []).map((r) => ({
    code: r[3],
    label: branches[r[3]]!,
    value: r[4 + flowMetric] as number | null,
  }));
  return (
    <>
      <Section tone="light" className="py-12 md:py-16">
        <PageHeader
          eyebrow="Arbetsmarknad"
          title="Hur väl matchar utbildningen arbetsmarknaden?"
          intro="Jämför matchning mellan utbildning och yrke, följ utvecklingen och se vilka branscher de utbildade arbetar i."
        />
      </Section>
      <Section className="py-10">
        <div className="grid items-start gap-8 lg:grid-cols-[280px_minmax(0,1fr)]">
          <aside className="space-y-5 rounded-xl border border-border bg-surface p-5">
            <h2 className="text-xl">Välj urval</h2>
            <label className="block">
              Geografi
              <select className={control} value={geo} onChange={(e) => changeGeo(e.target.value)}>
                {Object.entries(regions).map(([code, label]) => (
                  <option key={code} value={code}>
                    {label}
                  </option>
                ))}
              </select>
            </label>
            <label className="block">
              År
              <select
                className={control}
                value={period}
                onChange={(e) => setPeriod(e.target.value)}
              >
                {catalog.periods.map((p) => (
                  <option key={p}>{p}</option>
                ))}
              </select>
            </label>
            <label className="block">
              Kön
              <select
                className={control}
                value={sex}
                onChange={(e) => setSex(e.target.value as typeof sex)}
              >
                <option value="totalt">Totalt</option>
                <option value="2">Kvinnor</option>
                <option value="1">Män</option>
              </select>
            </label>
            <label className="block">
              Utbildningsindelning
              <select
                className={control}
                value={classification}
                onChange={(e) => {
                  setClassification(e.target.value);
                  setGroup({ grupp: "00S", niva: "00N", inriktning: "00I" }[e.target.value]!);
                }}
              >
                <option value="grupp">Utbildningsgrupp</option>
                <option value="niva">Utbildningsnivå</option>
                <option value="inriktning">Utbildningsinriktning</option>
              </select>
            </label>
            <label className="block">
              Utbildning
              <select className={control} value={group} onChange={(e) => setGroup(e.target.value)}>
                {groups[classification]!.map((code) => (
                  <option key={code} value={code}>
                    {education[code]}
                  </option>
                ))}
              </select>
            </label>
            <label className="block">
              Mått
              <select
                className={control}
                value={metric}
                onChange={(e) => setMetric(Number(e.target.value))}
              >
                {matchingMetrics.map((m, i) => (
                  <option key={i} value={i}>
                    {m.label}
                  </option>
                ))}
              </select>
            </label>
            <MunicipalityMap
              geo={geo}
              onGeo={changeGeo}
              values={Object.fromEntries(
                comparisons
                  .filter((r) => r.code.length === 4 && r.code.startsWith("25"))
                  .map((r) => [
                    r.code,
                    { value: r.value, label: `${matchingNumber(r.value)} ${unit}` },
                  ]),
              )}
              valueDescription={metricName}
            />
          </aside>
          <div className="min-w-0 space-y-10">
            <p className="text-lg">
              <strong>{name}</strong> · {period} ·{" "}
              {sex === "totalt" ? "Totalt" : sex === "2" ? "Kvinnor" : "Män"} · {education[group]}
            </p>
            {(query.isError || comparison.isError) && (
              <p role="alert">
                Statistiken kunde inte läsas.{" "}
                <button
                  className="underline"
                  onClick={() => {
                    void query.refetch();
                    void comparison.refetch();
                  }}
                >
                  Försök igen
                </button>
              </p>
            )}
            {query.isPending && <p role="status">Läser matchningsstatistik…</p>}
            {query.data && (
              <>
                <div className="grid gap-5 sm:grid-cols-2">
                  {[6, 5].map((index) => (
                    <div key={index} className="rounded-xl bg-brand-light p-6">
                      <h2 className="text-lg">{matchingMetrics[index]!.label}</h2>
                      <p className="mt-3 text-3xl font-bold">
                        {matchingNumber(matchingValue(point, index))}
                        {matchingValue(point, index) !== null && " %"}
                      </p>
                    </div>
                  ))}
                </div>
                <Figure title="Vilka utbildningar har högst matchning?">
                  <p className="mb-5 text-ink-muted">
                    {metricName}, {unit}. Klicka på en utbildning för att följa den över tid.
                    Totalgrupper ingår inte i rangordningen.
                  </p>
                  <MatchingRanking
                    rows={ranking}
                    unit={unit}
                    name={metricName}
                    onSelect={setGroup}
                  />
                </Figure>
                <Figure title="Hur har matchningen förändrats över tid?">
                  <p className="mb-5 text-ink-muted">
                    {education[group]} · {metricName}, {unit}. Luckor visar saknade uppgifter.
                  </p>
                  <MatchingHistory rows={history} unit={unit} name={name} />
                </Figure>
                <Figure title="Hur skiljer sig matchningen mellan geografier?">
                  <label className="mb-5 block max-w-sm">
                    Jämför
                    <select
                      className={control}
                      value={level}
                      onChange={(e) => setLevel(e.target.value)}
                    >
                      <option value="kommun">Kommunerna i {regions[county]}</option>
                      <option value="län">Alla län</option>
                    </select>
                  </label>
                  {comparison.isPending ? (
                    <p role="status">Läser jämförelsen…</p>
                  ) : comparison.isError ? (
                    <p>Jämförelsen kunde inte läsas.</p>
                  ) : (
                    <MatchingRanking
                      rows={selectedComparison}
                      unit={unit}
                      name={metricName}
                      onSelect={changeGeo}
                    />
                  )}
                </Figure>
                <Figure title="I vilka branscher arbetar de utbildade?">
                  <label className="mb-5 block max-w-sm">
                    Matchning
                    <select
                      className={control}
                      value={flowMetric}
                      onChange={(e) => setFlowMetric(Number(e.target.value))}
                    >
                      {matchingMetrics.slice(0, 4).map((m, i) => (
                        <option key={i} value={i}>
                          {m.label}
                        </option>
                      ))}
                    </select>
                  </label>
                  {query.data.hasFlows ? (
                    <BranchFlow rows={flows} label={matchingMetrics[flowMetric]!.label} />
                  ) : (
                    <p>
                      Branschflöden visas för riket, alla län och Norrbottens kommuner. Välj länet
                      för att se branschfördelningen.
                    </p>
                  )}
                </Figure>
              </>
            )}
            <section className="rounded-xl border border-border p-6">
              <h2 className="text-2xl">Vad visar statistiken?</h2>
              <div className="mt-5 space-y-4 leading-relaxed text-ink-muted">
                <p>
                  Matchad förvärvsgrad är helt matchade anställda dividerat med justerat antal
                  personer med utbildningen. Förvärvsgrad (justerad) omfattar helt, delvis och inte
                  matchade anställda. Nämnaren utesluter egenföretagare, studerande och anställda
                  utan tillräckliga yrkesuppgifter. Måtten beskriver folkbokförda 20–69 år och ska
                  inte blandas ihop med en vanlig sysselsättningsgrad.
                </p>
                <p>
                  Helt matchad innebär att både ämnesinriktning och utbildningsnivå stämmer överens
                  med yrket enligt SCB:s bedömning. En låg matchningsgrad behöver inte betyda låg
                  efterfrågan: yrkesuppgifter, utbildningarnas innehåll och andra faktorer kan
                  påverka resultatet.
                </p>
                <p>
                  Utbildningsgrupperna omfattar specifika utbildningar med examen. Totalen för
                  utbildningsgrupper har därför en annan population än totalen för utbildningsnivå
                  eller utbildningsinriktning. Grupperna ska inte summeras över indelningarna.
                </p>
                <p>
                  SCB:s sekretessmetod CKM tillför liten slumpmässig osäkerhet till antal. Delar
                  summerar därför inte alltid till totalen. Procenttal hämtas direkt från SCB.
                  Prickade värden behålls som saknade, aldrig som noll. Andelar publiceras bara när
                  SCB:s krav på bland annat gruppstorlek och yrkesuppgifter är uppfyllda.
                </p>
                <p>
                  E3 har ingen dimension för enskilda yrken. Flödena visar utbildning till bransch.
                  Kategorien ”uppgift saknas” kan även omfatta arbetslösa och personer utanför
                  arbetskraften; den ska inte tolkas som en bransch.
                </p>
                <details>
                  <summary className="cursor-pointer underline">SCB:s originalnoter</summary>
                  {catalog.notes.map((note, i) => (
                    <p key={i} className="mt-4 whitespace-pre-line">
                      {note}
                    </p>
                  ))}
                </details>
                <p>
                  <a href={catalog.source} target="_blank" rel="noreferrer" className="underline">
                    Öppna SCB:s tabell E3
                  </a>{" "}
                  · Hämtad {catalog.fetched.slice(0, 10)} · År {catalog.periods[0]}–
                  {catalog.periods.at(-1)}.
                </p>
              </div>
            </section>
          </div>
        </div>
      </Section>
    </>
  );
}
