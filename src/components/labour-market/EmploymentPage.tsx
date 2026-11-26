import { useState, type ReactNode } from "react";
import { useNavigate, useSearch } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import snapshot from "@/data/employment/catalog.json";
import { DEFAULT_GEO_CODE } from "@/config/geo";
import { getEmploymentSlice, getEmploymentComparison } from "@/lib/aggregates.functions";
import {
  employmentSeries,
  employmentNumber,
  metricNames,
  type EmploymentCatalog,
  type EmploymentMetric,
} from "@/lib/employment";
import { Section } from "@/components/layout/Section";
import { PageHeader } from "@/components/ui/PageHeader";
import { MunicipalityMap } from "@/components/geography/MunicipalityMap";
import { EmploymentChart } from "./EmploymentCharts";
const catalog = snapshot as EmploymentCatalog;
const control = "mt-2 w-full rounded-md border border-border bg-surface p-2 text-base font-normal";
function Select({
  label,
  value,
  onChange,
  children,
}: {
  label: string;
  value: string;
  onChange: (s: string) => void;
  children: ReactNode;
}) {
  return (
    <label className="mt-5 block text-sm font-semibold">
      {label}
      <select className={control} value={value} onChange={(e) => onChange(e.target.value)}>
        {children}
      </select>
    </label>
  );
}
function Figure({
  id,
  title,
  intro,
  source,
  children,
}: {
  id: string;
  title: string;
  intro: string;
  source: string;
  children: ReactNode;
}) {
  return (
    <section
      id={id}
      className="min-w-0 scroll-mt-28 rounded-xl border border-border bg-surface p-5 md:p-8"
    >
      <h2 className="text-2xl md:text-3xl">{title}</h2>
      <p className="mb-6 mt-3 leading-relaxed text-ink-muted">{intro}</p>
      {children}
      <p className="mt-6 border-t border-border pt-4 text-sm text-ink-muted">{source}</p>
    </section>
  );
}
export function EmploymentPage() {
  const search = useSearch({ strict: false }) as { geo?: string };
  const navigate = useNavigate();
  const geo = search.geo && search.geo in catalog.geographies ? search.geo : DEFAULT_GEO_CODE;
  const [dataset, setDataset] = useState("industry-month");
  const info = catalog.datasets[dataset]!;
  const [selectedSex, setSex] = useState("1+2");
  const sex = (
    info.selection["Kon"]?.includes(selectedSex)
      ? selectedSex
      : (info.selection["Kon"]?.[0] ?? "1+2")
  ) as "1" | "2" | "1+2";
  const [location, setLocation] = useState("bostad");
  const perspective = (info.perspectives.includes(location) ? location : info.perspectives[0]!) as
    "arbetsstalle" | "bostad";
  const [selectedCategory, setCategory] = useState("");
  const category =
    selectedCategory in info.categories
      ? selectedCategory
      : (info.total ?? Object.keys(info.categories)[0]!);
  const [selectedPeriod, setPeriod] = useState("");
  const period = info.periods.includes(selectedPeriod) ? selectedPeriod : info.periods.at(-1)!;
  const [selectedMetric, setMetric] = useState<EmploymentMetric>("count");
  const metrics = [
    "count",
    ...(info.total ? ["share"] : []),
    ...(info.rate ? ["rate"] : []),
    "change",
    "percent",
  ] as EmploymentMetric[];
  const metric = metrics.includes(selectedMetric) ? selectedMetric : "count";
  const unit = metric === "share" || metric === "rate" || metric === "percent" ? "%" : "personer";
  const [level, setLevel] = useState<"kommun" | "lan">("kommun");
  const [years, setYears] = useState("all");
  const county = geo === "00" ? DEFAULT_GEO_CODE : geo.slice(0, 2);
  const changeGeo = (value: string) =>
    void navigate({
      to: ".",
      search: (previous: Record<string, unknown>) => ({ ...previous, geo: value }),
      replace: true,
    });
  const query = useQuery({
    queryKey: ["employment", dataset, geo, sex, perspective],
    queryFn: () => getEmploymentSlice({ data: { dataset, geo, sex, perspective } }),
    staleTime: 3600000,
  });
  const national = useQuery({
    queryKey: ["employment", dataset, "00", sex, perspective],
    queryFn: () => getEmploymentSlice({ data: { dataset, geo: "00", sex, perspective } }),
    staleTime: 3600000,
  });
  const comparison = useQuery({
    queryKey: [
      "employment-comparison",
      dataset,
      period,
      sex,
      perspective,
      category,
      county,
      level,
      metric,
    ],
    queryFn: () =>
      getEmploymentComparison({
        data: { dataset, period, sex, perspective, category, county, level, metric },
      }),
    staleTime: 3600000,
  });
  const series = employmentSeries(query.data ?? [], info, sex, perspective, category, metric);
  const country = new Map(
    employmentSeries(national.data ?? [], info, sex, perspective, category, metric).map((r) => [
      r.period,
      r,
    ]),
  );
  const start = years === "all" ? "0000" : String(Number(period.slice(0, 4)) - Number(years));
  const chartRows = series
    .filter((r) => r.period <= period && r.period >= start)
    .map((r) => ({
      label: r.period.replace("M", "-"),
      value: r.value,
      other: geo === "00" ? null : (country.get(r.period)?.value ?? null),
      otherStatus: country.get(r.period)?.status ?? "",
      status: r.status,
      segment: dataset.endsWith("-year")
        ? r.period < "2022"
          ? "before2022"
          : r.period < "2024"
            ? "before2024"
            : "from2024"
        : "all",
    }));
  const categories = Object.entries(info.categories)
    .filter(([c]) => c !== info.total)
    .map(([code, label]) => {
      const point = employmentSeries(query.data ?? [], info, sex, perspective, code, metric).find(
        (r) => r.period === period,
      );
      return { label, value: point?.value ?? null, status: point?.status ?? "" };
    })
    .sort((a, b) => (b.value ?? -Infinity) - (a.value ?? -Infinity));
  const ranking = [...(comparison.data ?? [])].sort(
    (a, b) => (b.value ?? -Infinity) - (a.value ?? -Infinity),
  );
  const name = catalog.geographies[geo]!;
  const sexName = sex === "1" ? "Män" : sex === "2" ? "Kvinnor" : "Samtliga kön";
  const reference = `${name} · ${sexName} · ${info.age} · ${perspective === "bostad" ? "Bostadens belägenhet (nattbefolkning)" : "Arbetsställets belägenhet (dagbefolkning)"}`;
  const source = `Källa: SCB, ${info.table}. ${info.label}. Referensperiod: ${period.replace("M", "-")}. Källa uppdaterad ${info.updated.slice(0, 10)}.`;
  const hasError = query.isError || national.isError;
  return (
    <div className="font-normal">
      <Section tone="light" className="py-9 md:py-12">
        <PageHeader
          eyebrow="Arbetsmarknad · Sysselsättning"
          title="Hur utvecklas sysselsättningen?"
          intro="Se hur många som arbetar, inom vilka branscher och hur utvecklingen skiljer sig mellan grupper och platser."
        />
        <nav
          aria-label="Sidans avsnitt"
          className="mt-6 flex flex-wrap gap-x-6 gap-y-3 text-brand-dark"
        >
          {[
            ["utveckling", "Utveckling"],
            ["branscher", "Branscher och grupper"],
            ["geografi", "Jämför geografier"],
            ["definitioner", "Källor och definitioner"],
          ].map(([id, label]) => (
            <a key={id} href={`#${id}`} className="underline underline-offset-4">
              {label}
            </a>
          ))}
        </nav>
        <p className="mt-6 max-w-4xl text-sm leading-relaxed text-ink-muted">
          BAS månadsdata, BAS årliga register och RAMS visas som separata underlag. Byte av underlag
          ändrar både referensperiod och ibland åldersgrupp. Ingen förändring beräknas mellan dessa
          serier.
        </p>
      </Section>
      <Section className="py-9 md:py-12">
        <div className="grid items-start gap-8 xl:grid-cols-[270px_minmax(0,1fr)]">
          <aside
            className="rounded-xl border border-border bg-surface p-5 xl:sticky xl:top-24"
            aria-label="Statistikens urval"
          >
            <h2 className="text-xl">Välj vad du vill jämföra</h2>
            <Select
              label="Underlag och uppdelning"
              value={dataset}
              onChange={(v) => {
                setDataset(v);
                setCategory("");
                setPeriod("");
              }}
            >
              {Object.entries(catalog.datasets).map(([id, d]) => (
                <option key={id} value={id}>
                  {d.label}
                </option>
              ))}
            </Select>
            <Select label="Geografi" value={geo} onChange={changeGeo}>
              {["Riket", "Län", "Kommuner"].map((label, i) => (
                <optgroup label={label} key={label}>
                  {Object.entries(catalog.geographies)
                    .filter(([g]) =>
                      i === 0
                        ? g === "00"
                        : i === 1
                          ? g.length === 2 && g !== "00"
                          : g.length === 4,
                    )
                    .sort((a, b) => a[1].localeCompare(b[1], "sv"))
                    .map(([g, label]) => (
                      <option key={g} value={g}>
                        {label}
                      </option>
                    ))}
                </optgroup>
              ))}
            </Select>
            <Select label="Kön" value={sex} onChange={setSex}>
              {info.selection["Kon"]?.map((s) => (
                <option key={s} value={s}>
                  {s === "1" ? "Män" : s === "2" ? "Kvinnor" : "Samtliga"}
                </option>
              ))}
            </Select>
            <Select label="Geografiskt perspektiv" value={perspective} onChange={setLocation}>
              {info.perspectives.map((p) => (
                <option key={p} value={p}>
                  {p === "bostad" ? "Bostadens belägenhet" : "Arbetsställets belägenhet"}
                </option>
              ))}
            </Select>
            <Select label="Bransch eller grupp" value={category} onChange={setCategory}>
              {Object.entries(info.categories).map(([c, label]) => (
                <option key={c} value={c}>
                  {label}
                </option>
              ))}
            </Select>
            <Select label="Mått" value={metric} onChange={(v) => setMetric(v as EmploymentMetric)}>
              {metrics.map((m) => (
                <option key={m} value={m}>
                  {metricNames[m]}
                </option>
              ))}
            </Select>
            <Select label="Referensperiod" value={period} onChange={setPeriod}>
              {[...info.periods].reverse().map((p) => (
                <option key={p} value={p}>
                  {p.replace("M", "-")}
                </option>
              ))}
            </Select>
            <Select label="Visa historik" value={years} onChange={setYears}>
              <option value="all">Hela underlagets historik</option>
              <option value="10">Senaste tio åren</option>
              <option value="5">Senaste fem åren</option>
            </Select>
            <p className="mt-5 text-sm text-ink-muted">
              {info.age}.{" "}
              {metric === "change" || metric === "percent"
                ? "Förändring mot samma månad föregående år, eller föregående år för årsdata."
                : metric === "share"
                  ? "Andel av samtliga sysselsatta i samma underlag, kön och geografi. Detta är inte sysselsättningsgrad."
                  : metric === "rate"
                    ? "Sysselsatta som andel av befolkningen i samma grupp. SCB:s publicerade mått."
                    : ""}
            </p>
            <MunicipalityMap geo={geo} onGeo={changeGeo} />
          </aside>
          <div className="min-w-0 space-y-10 md:space-y-14">
            {hasError ? (
              <p role="alert" className="rounded-xl border border-border p-6">
                Statistiken kunde inte läsas.{" "}
                <button
                  className="underline"
                  onClick={() => {
                    void query.refetch();
                    void national.refetch();
                  }}
                >
                  Försök igen
                </button>
              </p>
            ) : query.isPending ? (
              <p role="status" className="p-6">
                Hämtar sysselsättningsstatistik…
              </p>
            ) : (
              <>
                <Figure
                  id="utveckling"
                  title="Hur har sysselsättningen utvecklats?"
                  intro={`${reference}. ${info.categories[category]}. ${metricNames[metric]}.`}
                  source={source}
                >
                  <EmploymentChart
                    key={`${dataset}-${metric}`}
                    rows={chartRows}
                    unit={unit}
                    name={name}
                  />
                  {dataset.endsWith("-year") && (
                    <p className="mt-5 text-sm text-ink-muted">
                      BAS årsregister har ändrade dataleveranser från 2022 och justerad
                      företagaravgränsning från 2024. Linjen bryts vid dessa gränser och
                      förändringar över dem visas inte. Befolkningsgrupperna avser 31 december,
                      sysselsättningen november.
                    </p>
                  )}
                </Figure>
                <Figure
                  id="branscher"
                  title={
                    info.dimension === "SNI2007"
                      ? metric === "change" || metric === "percent"
                        ? "Vilka branscher växer eller minskar?"
                        : "Inom vilka branscher arbetar befolkningen?"
                      : "Hur skiljer sig sysselsättningen mellan grupper?"
                  }
                  intro={`${reference}. ${metricNames[metric]}. Byt mått för att jämföra storlek, andel eller förändring.`}
                  source={source}
                >
                  <EmploymentChart rows={categories} unit={unit} rank name={metricNames[metric]} />
                  {info.dimension === "ArbetsSektor" && (
                    <p className="mt-5 text-sm text-ink-muted">
                      Offentlig förvaltning omfattar staten, kommun och region och överlappar därför
                      dessa tre rader. Näringslivet är SCB:s sektorkategori och är inte en exakt
                      synonym till privat sektor. Raderna ska inte summeras.
                    </p>
                  )}
                </Figure>
              </>
            )}
            <Figure
              id="geografi"
              title="Hur skiljer sig utvecklingen mellan platser?"
              intro={`${info.categories[category]}. ${sexName}. ${info.age}. ${metricNames[metric]}. ${perspective === "bostad" ? "Bostadens" : "Arbetsställets"} belägenhet.`}
              source={source}
            >
              <div className="mb-6 max-w-sm">
                <Select
                  label="Jämför geografier"
                  value={level}
                  onChange={(v) => setLevel(v as typeof level)}
                >
                  <option value="kommun">Kommuner i {catalog.geographies[county]}</option>
                  <option value="lan">Alla län</option>
                </Select>
              </div>
              {comparison.isError ? (
                <p role="alert">
                  Jämförelsen kunde inte läsas.{" "}
                  <button className="underline" onClick={() => void comparison.refetch()}>
                    Försök igen
                  </button>
                </p>
              ) : comparison.isPending ? (
                <p role="status">Hämtar jämförelse…</p>
              ) : (
                <EmploymentChart rows={ranking} unit={unit} rank name={metricNames[metric]} />
              )}
            </Figure>
            <section
              id="definitioner"
              className="scroll-mt-28 rounded-xl bg-brand-light p-6 md:p-8"
            >
              <h2 className="text-2xl">Vad behöver jag veta för att tolka statistiken?</h2>
              <div className="mt-5 space-y-4 text-sm leading-relaxed">
                <p>
                  <strong>Bostad och arbetsplats:</strong> Nattbefolkning avser sysselsatta som bor
                  i området. Dagbefolkning avser sysselsatta med arbetsställe i området. BAS
                  beskriver den folkbokförda befolkningen; personer som bor utomlands och arbetar
                  här täcks därför inte fullständigt. Antal personer är inte antal anställningar
                  eller arbetade timmar.
                </p>
                <p>
                  <strong>Månads- och årsdata:</strong> BAS preliminära månadsdata är inte
                  säsongrensade. Det slutliga årliga registret avser sysselsättning i november och
                  ska inte läsas som ett årsgenomsnitt. Det kan avvika från preliminära
                  novemberuppgifter. Månadsserierna börjar 2020 och fyller ännu inte tio år.
                </p>
                <p>
                  <strong>Metodbrott:</strong> RAMS äldre serie visas från 2011, efter
                  metodändringen för äldre. RAMS 2019–2021 använder ny källa och metod samt en annan
                  åldersavgränsning. BAS börjar 2020 och överlappar RAMS 2020–2021, men har andra
                  metoder, bland annat för företagare och arbetsställe. Serierna länkas inte och
                  överlappande år summeras inte. En längre kalenderhistorik innebär här flera
                  separata serier.
                </p>
                <p>
                  <strong>Grupper och andelar:</strong> Ålder och födelseregion hämtas från BAS
                  arbetsmarknadsstatus. Sysselsättningsgrad efter utbildning avser fast 20–64 år
                  genom hela månadsserien. Årligt antal efter utbildning avser 15–74 år. Grupperna
                  kan överlappa i åldersvyn och ska inte summeras. Branschernas andelar använder
                  SCB:s total, aldrig summan av redovisade delar. Ingen sysselsättningsgrad beräknas
                  för dagbefolkningen.
                </p>
                <p>
                  <strong>Skyddade och saknade uppgifter:</strong> 0 är ett publicerat nollvärde.
                  Null och SCB:s statusmarkeringar blir inte noll; statuskoden visas i datatabellen.
                  Skyddade celler beräknas inte baklänges från totaler. SCB använder också en
                  skyddsmetod som kan göra att delar inte summerar exakt till totalen. Saknade
                  värden bryter linjen; procentuell förändring saknas när jämförelsevärdet är noll.
                </p>
                <p>
                  <strong>Regionala matchningsindikatorer:</strong> RMI:s branschstruktur R3a och
                  förändring R3b avser 20–64 år och dagbefolkning. R3a har ett angivet källbyte till
                  BAS 2022 och är därför inte en obruten alternativ tidsserie. Här används separata
                  ursprungstabeller. Utbildningsmatchning E3 och utbildningsflöden U3 finns i
                  befintliga importflöden och används inte som ersättning för antal sysselsatta.
                </p>
                <p>
                  <a
                    className="underline underline-offset-4"
                    href="https://www.scb.se/AM0210"
                    target="_blank"
                    rel="noreferrer"
                  >
                    SCB: BAS och dokumentation
                  </a>{" "}
                  ·{" "}
                  <a
                    className="underline underline-offset-4"
                    href="https://www.scb.se/AM0207"
                    target="_blank"
                    rel="noreferrer"
                  >
                    SCB: RAMS och metodförändringar
                  </a>{" "}
                  ·{" "}
                  <a
                    className="underline underline-offset-4"
                    href={info.source}
                    target="_blank"
                    rel="noreferrer"
                  >
                    Metadata för valt underlag ({info.table})
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
