import { UvasSection } from "./UvasSection";
import { countAxis } from "@/lib/education-axis";
import { useState, type ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { useNavigate, useSearch } from "@tanstack/react-router";
import { Section } from "@/components/layout/Section";
import { PageHeader } from "@/components/ui/PageHeader";
import { MunicipalityMap } from "@/components/geography/MunicipalityMap";
import { DEFAULT_GEO_CODE } from "@/config/geo";
import {
  getAfUnemployment,
  getAfUnemploymentComparison,
  getAfUnemploymentGroups,
} from "@/lib/aggregates.functions";
import {
  afChange,
  afGroups,
  afNumber,
  afRate,
  afSeries,
  monthOffset,
  rollingAf,
  type AfPair,
  type AfValue,
} from "@/lib/af-unemployment";
import catalog from "@/data/af/catalog.json";
import { UnemploymentChart } from "./UnemploymentChart";
const geographies: Record<string, { name: string; level: string; parent: string | null }> =
  catalog.geographies;
const selectClass = "mt-2 w-full rounded-md border border-border bg-surface px-3 py-2 text-base";
const empty = { pairs: [], history: [] };
const sexNames: Record<string, string> = { "": "Alla kön", K: "Kvinnor", M: "Män" };
function Figure({
  id,
  title,
  intro,
  period,
  children,
}: {
  id: string;
  title: string;
  intro: string;
  period: string;
  children: ReactNode;
}) {
  return (
    <section
      id={id}
      aria-labelledby={`${id}-title`}
      className="min-w-0 scroll-mt-28 rounded-xl border border-border bg-surface p-5 md:p-7"
    >
      <h2 id={`${id}-title`} className="text-2xl">
        {title}
      </h2>
      <p className="mt-3 max-w-3xl leading-relaxed text-ink-muted">{intro}</p>
      <div className="mt-7">{children}</div>
      <p className="mt-6 border-t border-border pt-4 text-sm text-ink-muted">
        <a
          href={catalog.source}
          target="_blank"
          rel="noreferrer"
          className="underline underline-offset-4"
        >
          Källa: Arbetsförmedlingen
        </a>{" "}
        · {period} · Hämtad {catalog.retrieved.slice(0, 10)}.{" "}
        <a href="#definitioner" className="underline underline-offset-4">
          Definitioner och jämförbarhet
        </a>
      </p>
    </section>
  );
}
function Difference({ value, unit }: { value: number | null; unit: string }) {
  return (
    <>
      {value !== null && value > 0 ? "+" : ""}
      {afNumber(value, unit === "procentenheter" ? 1 : 0)}
      {value !== null ? ` ${unit}` : ""}
    </>
  );
}
export function UnemploymentPage() {
  const search = useSearch({ strict: false }) as { geo?: string };
  const navigate = useNavigate();
  const geo = search.geo && geographies[search.geo] ? search.geo : DEFAULT_GEO_CODE;
  const [sex, setSex] = useState<"" | "K" | "M">("");
  const [group, setGroup] = useState("total");
  const [period, setPeriod] = useState(catalog.latest);
  const [mean, setMean] = useState(false);
  const [years, setYears] = useState("10");
  const [compareLevel, setCompareLevel] = useState("kommun");
  const [compareMetric, setCompareMetric] = useState("rate");
  const changeGeo = (value: string) =>
    void navigate({
      to: ".",
      search: (previous: Record<string, unknown>) => ({ ...previous, geo: value }),
      replace: true,
    });
  const query = useQuery({
    queryKey: ["af-unemployment", geo, sex],
    queryFn: () => getAfUnemployment({ data: { geo, sex } }),
    staleTime: 3600000,
  });
  const national = useQuery({
    queryKey: ["af-unemployment", "00", sex],
    queryFn: () => getAfUnemployment({ data: { geo: "00", sex } }),
    staleTime: 3600000,
  });
  const comparison = useQuery({
    queryKey: ["af-comparison", period, group, sex],
    queryFn: () => getAfUnemploymentComparison({ data: { period, group: group as "total", sex } }),
    staleTime: 3600000,
  });
  const previous = useQuery({
    queryKey: ["af-comparison", monthOffset(period, -12), group, sex],
    queryFn: () =>
      getAfUnemploymentComparison({
        data: { period: monthOffset(period, -12), group: group as "total", sex },
      }),
    enabled: catalog.periods.includes(monthOffset(period, -12)),
    staleTime: 3600000,
  });
  const raw = afSeries(query.data ?? empty, group, sex);
  const countryRaw = afSeries(national.data ?? empty, group, sex);
  const selected = mean ? rollingAf(raw) : raw;
  const country = new Map((mean ? rollingAf(countryRaw) : countryRaw).map((p) => [p.period, p]));
  const from = years === "all" ? "0000-00" : monthOffset(period, -Number(years) * 12 + 1);
  const chartRows = selected.filter((p) => p.period >= from && p.period <= period);
  const rateStart = chartRows.find((p) => p.rate !== null)?.period ?? period;
  const rateRows = chartRows.filter((p) => p.period >= rateStart);
  const current = raw.find((p) => p.period === period);
  const nationalCurrent = countryRaw.find((p) => p.period === period);
  const countChange = afChange(raw, period, "count");
  const priorCount = raw.find((p) => p.period === monthOffset(period, -12))?.count;
  const name = geographies[geo]!.name;
  const county =
    geographies[geo]!.level === "kommun"
      ? geographies[geo]!.parent!
      : geographies[geo]!.level === "län"
        ? geo
        : DEFAULT_GEO_CODE;
  const comparisonRows = (comparison.data ?? []).filter((r) =>
    compareLevel === "län"
      ? geographies[r.geo]?.level === "län"
      : geographies[r.geo]?.level === "kommun" && geographies[r.geo]?.parent === county,
  );
  const value = (r: { row: AfPair }): number | null =>
    compareMetric === "rate"
      ? afRate(r.row[3], r.row[4])
      : typeof r.row[3] === "number"
        ? r.row[3]
        : null;
  comparisonRows.sort((a, b) => (value(b) ?? -Infinity) - (value(a) ?? -Infinity));
  const mapData = Object.fromEntries(
    (comparison.data ?? []).map((r) => [
      r.geo,
      {
        value: afRate(r.row[3], r.row[4]),
        label: `${afNumber(afRate(r.row[3], r.row[4]), 1)}${afRate(r.row[3], r.row[4]) !== null ? " %" : ""}`,
      },
    ]),
  );
  const groupQuery = useQuery({
    queryKey: ["af-groups", geo, period],
    queryFn: () => getAfUnemploymentGroups({ data: { geo, period } }),
    staleTime: 3600000,
  });
  const groups = Object.keys(afGroups)
    .filter((g) => g !== "total")
    .map((g) => {
      const r = groupQuery.data?.find((r) => r[0] === period && r[1] === g && r[2] === sex);
      return { group: g, count: r?.[3], rate: afRate(r?.[3], r?.[4]) };
    });
  const groupAxis = countAxis(groups.map((r) => r.rate).filter((v): v is number => v !== null));
  const signed = (v: number | null) => `${v !== null && v > 0 ? "+" : ""}${afNumber(v, 1)}`;
  const old = new Map((previous.data ?? []).map((r) => [r.geo, r.row]));
  const hasError = query.isError || national.isError;
  return (
    <div className="font-normal">
      <Section tone="light" className="py-9 md:py-12">
        <PageHeader
          eyebrow="Arbetsmarknad · Arbetslöshet"
          title="Hur utvecklas arbetslösheten?"
          intro="Följ Arbetsförmedlingens inskrivna arbetslöshet. Jämför utvecklingen mellan platser och se hur den skiljer sig mellan grupper."
        />
        <nav
          aria-label="Sidans avsnitt"
          className="mt-6 flex flex-wrap gap-x-6 gap-y-3 text-brand-dark"
        >
          {[
            ["utveckling", "Utveckling"],
            ["antal", "Antal"],
            ["geografi", "Jämför geografier"],
            ["grupper", "Jämför grupper"],
            ["uvas", "Unga utan arbete eller studier"],
          ].map(([id, label]) => (
            <a key={id} href={`#${id}`} className="underline underline-offset-4">
              {label}
            </a>
          ))}
        </nav>
        <p className="mt-6 max-w-4xl text-sm leading-relaxed text-ink-muted">
          Inskrivna arbetslösa omfattar öppet arbetslösa och arbetslösa i program. Det är ett annat
          mått än SCB:s arbetslöshet i AKU eller BAS. BAS används här som källa till arbetskraftens
          storlek.
        </p>
      </Section>
      <Section className="py-9 md:py-12">
        <div className="grid items-start gap-8 xl:grid-cols-[250px_minmax(0,1fr)]">
          <aside
            className="rounded-xl border border-border bg-surface p-5 xl:sticky xl:top-24"
            aria-label="Statistikens urval"
          >
            <h2 className="text-xl">Välj vad du vill jämföra</h2>
            <label className="mt-5 block text-sm font-semibold">
              Geografi
              <select
                className={selectClass}
                value={geo}
                onChange={(e) => changeGeo(e.target.value)}
              >
                <option value="00">Riket</option>
                <optgroup label="Län">
                  {Object.entries(geographies)
                    .filter(([, g]) => g.level === "län")
                    .sort((a, b) => a[1].name.localeCompare(b[1].name, "sv"))
                    .map(([c, g]) => (
                      <option key={c} value={c}>
                        {g.name}
                      </option>
                    ))}
                </optgroup>
                <optgroup label="Kommuner">
                  {Object.entries(geographies)
                    .filter(([, g]) => g.level === "kommun")
                    .sort((a, b) => a[1].name.localeCompare(b[1].name, "sv"))
                    .map(([c, g]) => (
                      <option key={c} value={c}>
                        {g.name}
                      </option>
                    ))}
                </optgroup>
              </select>
            </label>
            <label className="mt-4 block text-sm font-semibold">
              Kön
              <select
                className={selectClass}
                value={sex}
                onChange={(e) => setSex(e.target.value as typeof sex)}
              >
                {Object.entries(sexNames).map(([s, n]) => (
                  <option key={s} value={s}>
                    {n}
                  </option>
                ))}
              </select>
            </label>
            <label className="mt-4 block text-sm font-semibold">
              Grupp
              <select
                className={selectClass}
                value={group}
                onChange={(e) => setGroup(e.target.value)}
              >
                {Object.entries(afGroups).map(([g, n]) => (
                  <option key={g} value={g}>
                    {n}
                  </option>
                ))}
              </select>
            </label>
            <label className="mt-4 block text-sm font-semibold">
              Referensmånad
              <select
                className={selectClass}
                value={period}
                onChange={(e) => setPeriod(e.target.value)}
              >
                {[...catalog.periods].reverse().map((p) => (
                  <option key={p} value={p}>
                    {p}
                  </option>
                ))}
              </select>
            </label>
            <label className="mt-4 block text-sm font-semibold">
              Historik
              <select
                className={selectClass}
                value={years}
                onChange={(e) => setYears(e.target.value)}
              >
                <option value="5">Senaste 5 åren</option>
                <option value="10">Senaste 10 åren</option>
                <option value="all">All tillgänglig historik</option>
              </select>
            </label>
            <label className="mt-4 flex items-start gap-2 text-sm">
              <input
                type="checkbox"
                checked={mean}
                onChange={(e) => setMean(e.target.checked)}
                className="mt-1"
              />
              Visa rullande 12-månadersmedel i linjediagrammen
            </label>
            <p className="mt-3 text-xs text-ink-muted">
              Nyckeltal och geografiska jämförelser visar alltid vald månad.
            </p>
          </aside>
          <div
            className="min-w-0 space-y-10 md:space-y-14"
            aria-busy={query.isPending || national.isPending}
          >
            <div>
              <h2 className="text-2xl">Hur ser läget ut i {name}?</h2>
              <p className="mt-2 text-ink-muted">
                {period} · {afGroups[group]} · {sexNames[sex]}
              </p>
              {hasError && (
                <p role="alert" className="mt-4">
                  Statistiken kunde inte läsas.{" "}
                  <button
                    onClick={() => {
                      void query.refetch();
                      void national.refetch();
                    }}
                    className="underline"
                  >
                    Försök igen
                  </button>
                </p>
              )}
              {query.isPending ? (
                <p role="status" className="py-8">
                  Hämtar statistik…
                </p>
              ) : (
                <div className="mt-5 grid gap-4 sm:grid-cols-2 2xl:grid-cols-4">
                  {[
                    [
                      "Andel inskrivna arbetslösa",
                      `${afNumber(current?.rate, 1)}${current?.rate != null ? " %" : ""}`,
                      "Av gruppens arbetskraft (BAS)",
                    ],
                    [
                      "Antal inskrivna arbetslösa",
                      afNumber(current?.suppressed ? "<5" : current?.count),
                      "Personer vid månadens slut",
                    ],
                    [
                      "Förändring på ett år",
                      <Difference value={countChange} unit="personer" />,
                      priorCount && countChange !== null
                        ? `${signed((countChange / priorCount) * 100)} % jämfört med ${monthOffset(period, -12)}`
                        : `Jämfört med ${monthOffset(period, -12)}`,
                    ],
                    [
                      "Skillnad mot riket",
                      <Difference
                        value={
                          current?.rate != null && nationalCurrent?.rate != null
                            ? current.rate - nationalCurrent.rate
                            : null
                        }
                        unit="procentenheter"
                      />,
                      "Andel i vald geografi minus rikets andel",
                    ],
                  ].map(([label, v, note], i) => (
                    <div key={i} className="rounded-xl border border-border bg-surface p-5">
                      <p className="text-sm text-ink-muted">{label}</p>
                      <p className="mt-3 text-2xl font-semibold text-brand-dark">{v}</p>
                      <p className="mt-3 text-xs leading-relaxed text-ink-muted">{note}</p>
                    </div>
                  ))}
                </div>
              )}
            </div>
            <Figure
              id="utveckling"
              title="Hur har andelen arbetslösa utvecklats?"
              intro={`${afGroups[group]} i ${name} och riket. Andel av respektive grupps arbetskraft, procent. ${mean ? "Medelvärde av 12 månaders andelar, inte en sammanräknad årsandel." : "Månadsdata vid månadens slut."}`}
              period={`${chartRows.find((r) => r.rate !== null)?.period ?? "–"}–${period}`}
            >
              <UnemploymentChart
                rows={rateRows.map((p) => ({
                  period: p.period,
                  selected: p.rate,
                  selectedSuppressed: p.suppressed,
                  countrySuppressed: country.get(p.period)?.suppressed ?? false,
                  country: geo === "00" ? null : (country.get(p.period)?.rate ?? null),
                }))}
                title="Andel inskrivna arbetslösa"
                name={name}
                unit="%"
              />
              <p className="mt-4 text-sm text-ink-muted">
                BAS-andelar finns från 2023. Utbildningsnivå från april 2024. Äldre RAMS-andelar
                kopplas inte ihop med denna serie.
              </p>
            </Figure>
            <Figure
              id="antal"
              title="Hur har antalet arbetslösa förändrats?"
              intro={`${afGroups[group]} i ${name} och riket. ${mean ? "Genomsnittligt antal under de senaste 12 månaderna." : "Antal personer vid månadens slut."}`}
              period={`${chartRows[0]?.period ?? "–"}–${period}`}
            >
              <UnemploymentChart
                rows={chartRows.map((p) => ({
                  period: p.period,
                  selected: p.count,
                  selectedSuppressed: p.suppressed,
                  countrySuppressed: country.get(p.period)?.suppressed ?? false,
                  country: geo === "00" ? null : (country.get(p.period)?.count ?? null),
                }))}
                title="Antal inskrivna arbetslösa"
                name={name}
                unit="personer"
              />
              <p className="mt-4 text-sm text-ink-muted">
                Antal för samtliga finns från {catalog.historyStart}; gruppserierna i denna vy
                börjar 2023. Antal i stora och små geografier påverkas av befolkningsstorleken.
                Använd andelsdiagrammet för nivåjämförelser.
              </p>
            </Figure>
            <Figure
              id="geografi"
              title="Hur skiljer sig arbetslösheten mellan kommuner och län?"
              intro={`Jämför samma grupp och månad. Kartan visar andelen i Norrbottens kommuner. Klicka på kartan eller ett ortnamn för att följa utvecklingen där.`}
              period={period}
            >
              <div className="flex flex-wrap gap-5">
                <label className="text-sm">
                  Jämför
                  <select
                    className={selectClass}
                    value={compareLevel}
                    onChange={(e) => setCompareLevel(e.target.value)}
                  >
                    <option value="kommun">Kommuner i {geographies[county]!.name}</option>
                    <option value="län">Alla län</option>
                  </select>
                </label>
                <label className="text-sm">
                  Mått
                  <select
                    className={selectClass}
                    value={compareMetric}
                    onChange={(e) => setCompareMetric(e.target.value)}
                  >
                    <option value="rate">Andel av arbetskraften (%)</option>
                    <option value="count">Antal personer</option>
                  </select>
                </label>
              </div>
              {comparison.isError && (
                <p role="alert" className="mt-4">
                  Jämförelsen kunde inte läsas.{" "}
                  <button className="underline" onClick={() => void comparison.refetch()}>
                    Försök igen
                  </button>
                </p>
              )}
              {comparison.isPending ? (
                <p role="status" className="py-8">
                  Hämtar jämförelse…
                </p>
              ) : (
                <div className="mt-5 grid items-start gap-6 lg:grid-cols-[minmax(180px,0.75fr)_minmax(0,1.5fr)]">
                  <MunicipalityMap geo={geo} onGeo={changeGeo} values={mapData} />
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <caption className="py-3 text-left font-semibold">
                        {afGroups[group]} · {sexNames[sex]} · {period}
                      </caption>
                      <thead>
                        <tr>
                          <th scope="col" className="p-2 text-left">
                            Geografi
                          </th>
                          <th scope="col" className="p-2 text-right">
                            {compareMetric === "rate" ? "Andel (%)" : "Antal"}
                          </th>
                          <th scope="col" className="p-2 text-right">
                            Förändring på ett år{compareMetric === "rate" ? " (pe)" : " (antal)"}
                          </th>
                        </tr>
                      </thead>
                      <tbody>
                        {comparisonRows.map((r) => {
                          const before = old.get(r.geo);
                          const prev =
                            compareMetric === "rate"
                              ? afRate(before?.[3], before?.[4])
                              : typeof before?.[3] === "number"
                                ? before[3]
                                : null;
                          const v = value(r);
                          const display: AfValue =
                            r.row[3] === "<5" || r.row[4] === "<5" ? "<5" : v;
                          return (
                            <tr
                              key={r.geo}
                              className={`border-t border-border ${r.geo === geo ? "bg-brand-light" : ""}`}
                            >
                              <th scope="row" className="p-2 text-left font-normal">
                                <button
                                  className="text-brand-dark underline underline-offset-4"
                                  onClick={() => changeGeo(r.geo)}
                                >
                                  {geographies[r.geo]!.name}
                                </button>
                              </th>
                              <td className="p-2 text-right tabular-nums">
                                {afNumber(display, compareMetric === "rate" ? 1 : 0)}
                              </td>
                              <td className="p-2 text-right tabular-nums">
                                <Difference
                                  value={v !== null && prev !== null ? v - prev : null}
                                  unit={compareMetric === "rate" ? "procentenheter" : "personer"}
                                />
                              </td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                    <p className="mt-3 text-xs text-ink-muted">
                      pe = procentenheter. Saknas motsvarande månad föregående år visas ingen
                      förändring.
                    </p>
                  </div>
                </div>
              )}
            </Figure>
            <Figure
              id="grupper"
              title="Vilka grupper har högst arbetslöshet?"
              intro={`Andel av arbetskraften inom varje grupp i ${name}, ${sexNames[sex]!.toLowerCase()}. Grupperna överlappar och ska inte summeras. Klicka på en grupp för dess historik.`}
              period={period}
            >
              {groupQuery.isPending && <p role="status">Hämtar gruppstatistik…</p>}
              {groupQuery.isError && (
                <p role="alert">
                  Gruppstatistiken kunde inte läsas.{" "}
                  <button className="underline" onClick={() => void groupQuery.refetch()}>
                    Försök igen
                  </button>
                </p>
              )}
              <div className="space-y-5" aria-busy={groupQuery.isPending}>
                {groups
                  .sort((a, b) => (b.rate ?? -Infinity) - (a.rate ?? -Infinity))
                  .map((r) => (
                    <div
                      key={r.group}
                      className="grid grid-cols-[minmax(0,1fr)_5rem] items-center gap-4"
                    >
                      <div>
                        <button
                          onClick={() => setGroup(r.group)}
                          className="text-left text-sm text-brand-dark underline underline-offset-4"
                        >
                          {afGroups[r.group]}
                        </button>
                        <div className="mt-2 h-3 rounded bg-brand-light">
                          <div
                            className="h-3 rounded bg-brand"
                            style={{
                              width: `${r.rate !== null ? (r.rate / groupAxis.maximum) * 100 : 0}%`,
                            }}
                          />
                        </div>
                      </div>
                      <span className="text-right text-sm tabular-nums">
                        {afNumber(r.rate, 1)}
                        {r.rate !== null ? " %" : ""}
                      </span>
                    </div>
                  ))}
              </div>
              <p className="mt-3 text-xs text-ink-muted">
                Gemensam skala: 0–{afNumber(groupAxis.maximum)} %.
              </p>
              <div className="mt-7 grid gap-4 sm:grid-cols-2">
                {(["K", "M"] as const).map((s) => {
                  const r = groupQuery.data?.find(
                    (r) => r[0] === period && r[1] === group && r[2] === s,
                  );
                  return (
                    r && (
                      <p key={s}>
                        {sexNames[s]}: {afNumber(afRate(r[3], r[4]), 1)} %
                      </p>
                    )
                  );
                })}
              </div>
              <p className="mt-4 text-sm text-ink-muted">
                Välj kvinnor eller män i filtret för att jämföra utvecklingen. Utbildningsnivå
                saknas före april 2024. Äldre avser källans åldersgrupp; se definitionerna nedan.
              </p>
            </Figure>
            {group === "total" && (
              <Figure
                id="program"
                title="Hur fördelas arbetslösheten mellan öppen arbetslöshet och program?"
                intro={`Antal i ${name}. Endast program som AF räknar som arbetslöshet ingår. Uppdelningen följer den längre arbetssökandefilen.`}
                period={`${chartRows[0]?.period ?? "–"}–${period}`}
              >
                <UnemploymentChart
                  rows={chartRows.map((p) => ({
                    period: p.period,
                    selected: p.open,
                    country: p.program,
                  }))}
                  title="Öppet arbetslösa och arbetslösa i program"
                  comparisonName="Arbetslösa i program"
                  name="Öppet arbetslösa"
                  unit="personer"
                />
                <p className="mt-4 text-sm text-ink-muted">
                  Den gula serien visar arbetslösa i program. Här jämförs två delar av
                  arbetslösheten i vald geografi.
                </p>
              </Figure>
            )}
            <UvasSection />
            <section
              id="definitioner"
              className="scroll-mt-28 rounded-xl bg-brand-light p-6 md:p-8"
            >
              <h2 className="text-2xl">Vad behöver jag veta för att tolka statistiken?</h2>
              <div className="mt-5 space-y-4 text-sm leading-relaxed">
                <p>
                  AF mäter personer som är inskrivna som arbetslösa vid månadens slut. SCB:s AKU
                  bygger på en urvalsundersökning och SCB:s BAS klassificerar befolkningens
                  arbetsmarknadsstatus. Måtten har olika definitioner och kan ge olika resultat.
                </p>
                <p>
                  Andel = AF:s publicerade antal inskrivna arbetslösa delat med AF:s BAS-arbetskraft
                  för samma grupp, kön, månad och geografi. Arbetskraften är ett eftersläpande
                  tolvmånadersgenomsnitt. Kommunernas andelar summeras eller medelvärdesberäknas
                  aldrig till län eller riket.
                </p>
                <p>
                  Åldersgränsen för samtliga är 16–64 år till 2022, 16–65 år 2023–2025 och 16–66 år
                  från 2026. Förändringar över dessa gränser påverkas även av det ändrade urvalet.
                  Unga avser 18–24 år. AF:s BAS-fil benämner äldre 55–64 år, medan underliggande
                  definitioner har ändrats; äldregruppen bör tolkas försiktigt vid jämförelser över
                  tid.
                </p>
                <p>
                  Rikets nämnare summerar BAS-filens arbetskraft för de 290 kommunerna. Täljaren
                  omfattar även AF:s restkategori för okänd geografi, så att inga inskrivna
                  arbetslösa tappas bort. Antalen har kontrollerats mot arbetssökandefilen för
                  samtliga gemensamma månader, geografier och kön.
                </p>
                <p>
                  0 är ett uppmätt nollvärde. Uppgift saknas betyder att ingen användbar uppgift
                  finns. Sekretessmarkerade värden visas som ”Sekretess” och blir inte noll. Saknade
                  eller sekretessmarkerade månader ger avbrott i linjen. Tolvmånadersmedel visas
                  bara när samtliga 12 månader är tillgängliga. Det är inte en säsongrensad serie.
                </p>
                <p>
                  MUCF:s årsstatistik om unga som varken arbetar eller studerar finns i
                  UVAS-avsnittet ovan.
                </p>
                <p>
                  <a
                    href="https://arbetsformedlingen.se/statistik/sok-statistik/forklaring-av-statistiken"
                    target="_blank"
                    rel="noreferrer"
                    className="underline underline-offset-4"
                  >
                    Läs Arbetsförmedlingens definitioner
                  </a>
                </p>
              </div>
            </section>
          </div>
        </div>
      </Section>
    </div>
  );
}
