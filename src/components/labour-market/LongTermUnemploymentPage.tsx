import { useState, type ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { useNavigate, useSearch } from "@tanstack/react-router";
import { PageHeader } from "@/components/ui/PageHeader";
import { Section } from "@/components/layout/Section";
import { DEFAULT_GEO_CODE } from "@/config/geo";
import {
  getAfDurationCatalog,
  getAfDurationHistory,
  getAfDurationGroups,
  getAfDurationComparison,
} from "@/lib/af-duration.functions";
import {
  afPeriod,
  durationLabels,
  durationText,
  type DurationMeasure,
  type DurationUnit,
} from "@/lib/af-duration";
import { DurationCharts } from "./DurationCharts";
import { DurationComparison } from "./DurationComparison";
const source =
  "https://arbetsformedlingen.se/statistik/sok-statistik/tidigare-statistik-tidsserier";
const selectClass =
  "mt-2 w-full rounded-md border border-border bg-surface py-2 pl-3 pr-8 text-base";
const groupLabels: Record<string, string> = {
  kön: "Kön",
  ålder: "Ålder",
  utbildningsnivå: "Utbildningsnivå",
  födelseland: "Födelseland",
};
function Figure({
  title,
  period,
  children,
}: {
  title: string;
  period: string;
  children: ReactNode;
}) {
  return (
    <section className="min-w-0 rounded-xl border border-border bg-surface p-5 md:p-7">
      <h2 className="text-2xl">{title}</h2>
      <div className="mt-7">{children}</div>
      <p className="mt-6 border-t border-border pt-4 text-sm text-ink-muted">
        <a href={source} target="_blank" rel="noreferrer" className="underline underline-offset-4">
          Källa: Arbetsförmedlingen, tid utan arbete och inskrivna arbetslösa
        </a>
        . Referensperiod: {period}.
      </p>
    </section>
  );
}
export function LongTermUnemploymentPage() {
  const search = useSearch({ strict: false }) as { geo?: string };
  const navigate = useNavigate();
  const [measure, setMeasure] = useState<DurationMeasure>("over12");
  const [unit, setUnit] = useState<DurationUnit>("count");
  const [selectedPeriod, setPeriod] = useState("");
  const [showBenchmark, setShowBenchmark] = useState(false);
  const [years, setYears] = useState("10");
  const [breakdown, setBreakdown] = useState("kön");
  const [comparisonLevel, setComparisonLevel] = useState("county");
  const catalog = useQuery({
    queryKey: ["af-duration-catalog"],
    queryFn: () => getAfDurationCatalog(),
    staleTime: 300000,
  });
  const geographies = catalog.data?.geographies ?? [];
  const names = Object.fromEntries(geographies.map((g) => [g.code, g.name]));
  const geo = search.geo && names[search.geo] ? search.geo : DEFAULT_GEO_CODE;
  const history = useQuery({
    queryKey: ["af-duration-history", geo],
    queryFn: () => getAfDurationHistory({ data: { geo } }),
    staleTime: 300000,
  });
  const national = useQuery({
    queryKey: ["af-duration-history", "00"],
    queryFn: () => getAfDurationHistory({ data: { geo: "00" } }),
    staleTime: 300000,
  });
  const periods = (history.data ?? []).map((r) => r.period);
  const period = periods.includes(selectedPeriod)
    ? selectedPeriod
    : (periods.at(-1) ?? catalog.data?.latest ?? "");
  const groups = useQuery({
    queryKey: ["af-duration-groups", geo, period],
    queryFn: () => getAfDurationGroups({ data: { geo, period } }),
    enabled: !!period,
    staleTime: 300000,
  });
  const comparison = useQuery({
    queryKey: ["af-duration-comparison", period],
    queryFn: () => getAfDurationComparison({ data: { period } }),
    enabled: !!period,
    staleTime: 300000,
  });
  const current = history.data?.find((r) => r.period === period);
  const start =
    years === "all" ? "" : `${Number(period.slice(0, 4)) - Number(years)}${period.slice(4)}`;
  const rows = (history.data ?? []).filter((r) => r.period >= start && r.period <= period);
  const parent =
    geo.length === 4
      ? (geographies.find((g) => g.code === geo)?.parent_code ?? geo.slice(0, 2))
      : geo === "00"
        ? "25"
        : geo;
  const comparisonRows = (comparison.data ?? []).filter(
    (r) =>
      r.geo_code === "00" ||
      (comparisonLevel === "county"
        ? r.geo_code.length === 2
        : r.geo_code === parent ||
          geographies.find((g) => g.code === r.geo_code)?.parent_code === parent),
  );
  const groupRows = (groups.data ?? [])
    .filter((r) => r.dimension_type === breakdown)
    .map((r) => ({
      ...r,
      dimension_value:
        r.dimension_value === "K"
          ? "Kvinnor"
          : r.dimension_value === "M"
            ? "Män"
            : r.dimension_value,
    }));
  const errors = [
    catalog.error,
    history.error,
    national.error,
    groups.error,
    comparison.error,
  ].filter(Boolean);
  const changeGeo = (value: string) =>
    void navigate({
      to: ".",
      search: (previous: Record<string, unknown>) => ({ ...previous, geo: value }),
      replace: true,
    });
  return (
    <>
      <Section tone="light" className="py-9 md:py-12">
        <PageHeader
          eyebrow="Arbetsmarknad · Långtidsarbetslöshet"
          title="Hur många har varit utan arbete en längre tid?"
          intro="Följ tiden utan arbete bland inskrivna arbetslösa. Jämför utvecklingen, grupper och geografiska områden."
        />
      </Section>
      <div className="mx-auto grid max-w-(--container-content) items-start gap-6 px-4 py-8 md:px-8 lg:grid-cols-[260px_minmax(0,1fr)] lg:gap-8">
        <aside
          aria-label="Filter för långtidsarbetslöshet"
          className="rounded-xl border border-border bg-surface p-5 lg:sticky lg:top-24"
        >
          <h2 className="text-lg">Filtrera sidan</h2>
          <div className="mt-5 space-y-5">
            <label className="block">
              Område
              <select
                className={selectClass}
                aria-label="Område"
                value={geo}
                onChange={(e) => changeGeo(e.target.value)}
              >
                {!geographies.length && <option value="25">Norrbottens län</option>}
                {[2, 4].map((length) => (
                  <optgroup key={length} label={length === 2 ? "Riket och län" : "Kommuner"}>
                    {geographies
                      .filter((g) => g.code.length === length)
                      .map((g) => (
                        <option key={g.code} value={g.code}>
                          {g.name}
                        </option>
                      ))}
                  </optgroup>
                ))}
              </select>
            </label>
            <label className="block">
              Tid utan arbete
              <select
                className={selectClass}
                aria-label="Tid utan arbete"
                value={measure}
                onChange={(e) => setMeasure(e.target.value as DurationMeasure)}
              >
                {Object.entries(durationLabels).map(([v, n]) => (
                  <option key={v} value={v}>
                    {n}
                  </option>
                ))}
              </select>
            </label>
            <label className="block">
              Visa
              <select
                className={selectClass}
                aria-label="Visa"
                value={unit}
                onChange={(e) => setUnit(e.target.value as DurationUnit)}
              >
                <option value="count">Antal personer</option>
                <option value="share">Andel av inskrivna arbetslösa</option>
              </select>
            </label>
            <label className="block">
              Månad
              <select
                className={selectClass}
                aria-label="Månad"
                value={period}
                onChange={(e) => setPeriod(e.target.value)}
              >
                {[...periods].reverse().map((p) => (
                  <option key={p} value={p}>
                    {afPeriod(p)}
                  </option>
                ))}
              </select>
            </label>
            <label className="block">
              Historik
              <select
                className={selectClass}
                aria-label="Historik"
                value={years}
                onChange={(e) => setYears(e.target.value)}
              >
                <option value="10">Senaste tio åren</option>
                <option value="5">Senaste fem åren</option>
                <option value="all">Hela tillgängliga historiken</option>
              </select>
            </label>
          </div>
          <p className="mt-5 text-sm text-ink-muted">
            Valt område: {names[geo] ?? "Norrbottens län"}. Staplingen visar alltid alla
            längdintervall.
          </p>
        </aside>
        <div className="min-w-0 space-y-10">
          {errors.length > 0 && (
            <p role="alert" className="rounded-lg border border-border bg-surface p-5">
              Statistiken kunde inte läsas fullständigt. Försök ladda om sidan.{" "}
              {String((errors[0] as Error).message)}
            </p>
          )}
          {history.isPending || catalog.isPending ? (
            <p role="status">Hämtar statistik …</p>
          ) : !rows.length ? (
            <p role="status">Inga publicerade uppgifter finns för det valda området.</p>
          ) : (
            <>
              <Figure title="Hur många har varit utan arbete länge?" period={afPeriod(period)}>
                <p className="mb-5 text-ink-muted">
                  {names[geo]} · {afPeriod(period)}
                </p>
                <div className="grid gap-5 sm:grid-cols-3">
                  {(["over6", "over12", "over24"] as const).map((m) => (
                    <div key={m} className="rounded-lg bg-brand-light p-5">
                      <h3 className="text-base">{durationLabels[m]}</h3>
                      <p className="mt-3 text-2xl tabular-nums">{durationText(current, m, unit)}</p>
                    </div>
                  ))}
                </div>
                <p className="mt-5 text-sm text-ink-muted">
                  Andelen utan arbete i mer än 12 månader är{" "}
                  {durationText(current, "over12", "share").toLocaleLowerCase("sv-SE")}. Nämnaren är
                  samtliga inskrivna arbetslösa i samma område och månad.
                </p>
              </Figure>
              <Figure
                title="Hur har tiden utan arbete förändrats?"
                period={`${afPeriod(rows[0]!.period)}–${afPeriod(rows.at(-1)!.period)}`}
              >
                <p className="mb-5 text-ink-muted">
                  {unit === "share" ? "Andel av inskrivna arbetslösa (%)" : "Antal personer"}.{" "}
                  {names[geo]}.
                </p>
                <label className="mb-5 flex items-center gap-3 text-sm">
                  <input
                    type="checkbox"
                    checked={showBenchmark}
                    disabled={geo === "00"}
                    onChange={(e) => setShowBenchmark(e.target.checked)}
                  />{" "}
                  Jämför tidsserien med Riket
                </label>
                <DurationCharts
                  chosenName={names[geo] ?? "Valt område"}
                  rows={rows}
                  benchmark={geo === "00" || !showBenchmark ? [] : (national.data ?? [])}
                  measure={measure}
                  unit={unit}
                />
              </Figure>
            </>
          )}
          {period && (
            <>
              <Figure title="Vilka grupper har längst tid utan arbete?" period={afPeriod(period)}>
                <label className="block max-w-sm">
                  Jämför efter
                  <select
                    className={selectClass}
                    aria-label="Jämför efter"
                    value={breakdown}
                    onChange={(e) => setBreakdown(e.target.value)}
                  >
                    {Object.entries(groupLabels).map(([v, n]) => (
                      <option key={v} value={v}>
                        {n}
                      </option>
                    ))}
                  </select>
                </label>
                <p className="my-5 text-sm text-ink-muted">
                  {durationLabels[measure]} i {names[geo]}. Välj andel för att jämföra hur vanligt
                  lång tid utan arbete är inom varje grupp. Uppdelningarna kan inte kombineras.
                </p>
                {groups.isPending ? (
                  <p role="status">Hämtar grupper …</p>
                ) : (
                  <DurationComparison
                    rows={groupRows}
                    names={{}}
                    measure={measure}
                    unit={unit}
                    title="Grupper efter tid utan arbete"
                  />
                )}
              </Figure>
              <Figure title="Hur skiljer sig kommunerna och länen?" period={afPeriod(period)}>
                <label className="block max-w-sm">
                  Geografisk jämförelse
                  <select
                    className={selectClass}
                    aria-label="Geografisk jämförelse"
                    value={comparisonLevel}
                    onChange={(e) => setComparisonLevel(e.target.value)}
                  >
                    <option value="county">Samtliga län och Riket</option>
                    <option value="municipality">Kommunerna i {names[parent] ?? "valt län"}</option>
                  </select>
                </label>
                <p className="my-5 text-sm text-ink-muted">
                  {durationLabels[measure]}. Samma referensmånad för alla områden. Klicka på ett
                  område för att följa dess utveckling.
                </p>
                {comparison.isPending ? (
                  <p role="status">Hämtar jämförelsen …</p>
                ) : (
                  <DurationComparison
                    rows={comparisonRows}
                    names={names}
                    measure={measure}
                    unit={unit}
                    title="Geografisk jämförelse"
                    onChoose={changeGeo}
                  />
                )}
              </Figure>
            </>
          )}
          <section className="rounded-xl border border-border bg-surface p-5 md:p-7">
            <h2 className="text-2xl">Vad mäter statistiken?</h2>
            <div className="mt-5 space-y-4 text-base leading-relaxed text-ink-muted">
              <p>
                Inskrivna arbetslösa omfattar öppet arbetslösa och arbetslösa i program. Tid utan
                arbete avser sammanhängande tid utan arbete enligt Arbetsförmedlingens register.
                Sidan använder källfilens gränser: mer än 6, 12 och 24 månader.
              </p>
              <p>
                Grupperna överlappar: personer med mer än 24 månader ingår även i mer än 12 och mer
                än 6 månader. Staplingen använder därför totalen minus mer än 6 månader, sedan
                differenserna 6–12 och 12–24 samt mer än 24 månader.
              </p>
              <p>
                Åldersomfattningen är 16–64 år 2006–2022, 16–65 år 2023–2025 och 16–66 år från 2026.
                Förändringar vid dessa årsskiften påverkas av att fler åldrar ingår. Månadsserierna
                är inte säsongsrensade.
              </p>
              <p>
                Noll betyder inga personer. Saknade uppgifter visas som saknade. Sekretessmarkerade
                tal visas separat; ett länsvärde kan vara en undre gräns när kommunuppgifter är
                maskerade. Då visas ingen exakt andel eller stapling. Riket hämtas från den separata
                riketsfilen för tid utan arbete.
              </p>
              <p>
                Andelar avser den valda gruppens inskrivna arbetslösa, inte befolkningen eller
                arbetskraften. Det går inte att dra slutsatser om genomsnittlig arbetslöshetstid
                från dessa intervall.
              </p>
              {catalog.data?.first && catalog.data.latest && (
                <p>
                  Tillgänglig rikshistorik: {afPeriod(catalog.data.first)}–
                  {afPeriod(catalog.data.latest)}. Senast hämtad:{" "}
                  {catalog.data.metadata
                    .map((m) => m.hamtad_datum)
                    .filter(Boolean)
                    .sort()
                    .at(-1) ?? "Uppgift saknas"}
                  .
                </p>
              )}
            </div>
          </section>
        </div>
      </div>
    </>
  );
}
