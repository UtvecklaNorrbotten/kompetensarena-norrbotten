import { useState, type ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { useNavigate, useSearch } from "@tanstack/react-router";
import { Section } from "@/components/layout/Section";
import { PageHeader } from "@/components/ui/PageHeader";
import { MunicipalityMap } from "@/components/geography/MunicipalityMap";
import { DEFAULT_GEO_CODE } from "@/config/geo";
import { getDemandSlice, getDemandComparison } from "@/lib/aggregates.functions";
import {
  demandNumber,
  demandValue,
  rollingDemand,
  type DemandSelection,
} from "@/lib/labour-demand";
import { monthOffset } from "@/lib/af-unemployment";
import catalog from "@/data/demand/catalog.json";
import { DemandRanking, DemandTimeChart } from "./DemandCharts";
import { DemandSeason } from "./DemandSeason";
import { DemandLor } from "./DemandLor";
const geos: Record<string, { name: string; level: string; parent: string | null }> =
  catalog.geographies;
const control = "mt-2 w-full rounded-md border border-border bg-surface px-3 py-2 text-base";
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
        <a href="#efterfragan-definitioner" className="underline">
          Definitioner och jämförbarhet
        </a>
      </p>
    </section>
  );
}
export function LabourDemandPage() {
  const search = useSearch({ strict: false }) as { geo?: string };
  const navigate = useNavigate();
  const geo = search.geo && geos[search.geo] ? search.geo : DEFAULT_GEO_CODE;
  const name = geos[geo]!.name;
  const county = geos[geo]!.level === "kommun" ? geos[geo]!.parent! : geo === "00" ? "25" : geo;
  const [field, setField] = useState("");
  const [group, setGroup] = useState("");
  const [metric, setMetric] = useState<"new" | "remaining">("new");
  const [duration, setDuration] = useState<"all" | "10">("all");
  const [period, setPeriod] = useState(catalog.latest);
  const [rolling, setRolling] = useState(false);
  const [years, setYears] = useState("10");
  const [level, setLevel] = useState<"kommun" | "län">("kommun");
  const selection: DemandSelection = {
    field,
    group,
    metric,
    duration: group ? "source" : duration,
  };
  const changeGeo = (g: string) =>
    void navigate({
      to: ".",
      search: (p: Record<string, unknown>) => ({ ...p, geo: g }),
      replace: true,
    });
  const chooseGroup = (g: string) => {
    setGroup(g);
    if (g) {
      setMetric("remaining");
      if (period < catalog.dimensions.groups.start) setPeriod(catalog.dimensions.groups.start);
    }
  };
  const query = useQuery({
    queryKey: ["demand", geo, selection, period],
    queryFn: () => getDemandSlice({ data: { geo, selection, period } }),
    staleTime: 3600000,
  });
  const national = useQuery({
    queryKey: ["demand", "00", selection, period],
    queryFn: () => getDemandSlice({ data: { geo: "00", selection, period } }),
    enabled: geo !== "00",
    staleTime: 3600000,
  });
  const comparison = useQuery({
    queryKey: ["demand-comparison", selection, period, county, level],
    queryFn: () => getDemandComparison({ data: { selection, period, county, level } }),
    staleTime: 3600000,
  });
  const mapQuery = useQuery({
    queryKey: ["demand-comparison", selection, period, "25", "kommun"],
    queryFn: () =>
      getDemandComparison({ data: { selection, period, county: "25", level: "kommun" } }),
    staleTime: 3600000,
  });
  const rows = query.data?.rows ?? [];
  const visible = rolling ? rollingDemand(rows, metric) : rows;
  const country = rolling
    ? rollingDemand(national.data?.rows ?? [], metric)
    : (national.data?.rows ?? []);
  const countryIndex = new Map(country.map((r) => [r.period, r.value]));
  const start = years === "all" ? "0000-00" : monthOffset(period, -Number(years) * 12 + 1);
  const chartRows = visible
    .filter((r) => r.period >= start && r.period <= period)
    .map((r) => ({
      ...r,
      comparison: geo === "00" ? undefined : (countryIndex.get(r.period) ?? null),
    }));
  const groups = Object.entries(catalog.groups)
    .sort(([a], [b]) => a.localeCompare(b))
    .filter(
      ([code]) =>
        !field || catalog.occupationRelations.some((r) => r[0] === field && r[1] === code),
    );
  const unit = rolling && metric === "remaining" ? "platser i månadsgenomsnitt" : "platser";
  const description = group ? `SSYK ${group}` : field || "Samtliga yrken";
  const metricName = metric === "new" ? "Nyanmälda platser" : "Kvarstående platser";
  const metricDefinition =
    metric === "new"
      ? "Platser som anmälts till Arbetsförmedlingen under månaden."
      : "Platser hos Arbetsförmedlingen som fortfarande går att söka vid månadens slut.";
  const sourceStart = group
    ? catalog.dimensions.groups.start
    : field
      ? catalog.dimensions.fields.start
      : catalog.dimensions.totals.start;
  const periods = catalog.dimensions.totals.periods.filter((p) => p >= sourceStart);
  const currentPeriod = periods.includes(period);
  return (
    <>
      <Section tone="light" className="py-12 md:py-16">
        <PageHeader
          eyebrow="Arbetsmarknad"
          title="Var och inom vilka yrken efterfrågas arbetskraft?"
          intro="Följ platser som anmälts till Arbetsförmedlingen och jämför yrken och geografier. SCB:s arbetsgivarundersökning kompletterar bilden av efterfrågan."
        />
        <p className="mt-5 max-w-3xl text-sm leading-relaxed text-ink-muted">
          En platsannons kan avse flera tjänster. Anmälda platser visar inte alla lediga jobb i
          ekonomin, och fler annonser behöver inte betyda större arbetskraftsbrist.
        </p>
      </Section>
      <Section className="py-10">
        <div className="grid items-start gap-8 lg:grid-cols-[17rem_minmax(0,1fr)]">
          <aside className="rounded-xl border border-border bg-surface p-5 lg:sticky lg:top-24 lg:max-h-[calc(100dvh-7rem)] lg:overflow-y-auto">
            <h2 className="text-xl">Välj vad du vill jämföra</h2>
            <div className="mt-5 grid gap-5 sm:grid-cols-2 lg:grid-cols-1">
              <label className="text-sm">
                Geografi
                <select value={geo} onChange={(e) => changeGeo(e.target.value)} className={control}>
                  {["riket", "län", "kommun"].map((l) => (
                    <optgroup
                      label={l === "riket" ? "Riket" : l === "län" ? "Län" : "Kommuner"}
                      key={l}
                    >
                      {Object.entries(geos)
                        .filter(([, g]) => g.level === l)
                        .sort((a, b) => a[1].name.localeCompare(b[1].name, "sv"))
                        .map(([c, g]) => (
                          <option value={c} key={c}>
                            {g.name}
                          </option>
                        ))}
                    </optgroup>
                  ))}
                </select>
              </label>
              <label className="text-sm">
                Yrkesområde
                <select
                  value={field}
                  onChange={(e) => {
                    setField(e.target.value);
                    setGroup("");
                  }}
                  className={control}
                >
                  <option value="">Samtliga yrkesområden</option>
                  {catalog.fields.map((f) => (
                    <option key={f}>{f}</option>
                  ))}
                </select>
              </label>
              <label className="text-sm">
                Yrkesgrupp (SSYK 2012)
                <select
                  value={group}
                  onChange={(e) => chooseGroup(e.target.value)}
                  className={control}
                >
                  <option value="">Samtliga yrkesgrupper</option>
                  {groups.map(([c, label]) => (
                    <option value={c} key={c}>
                      {c} {label}
                    </option>
                  ))}
                </select>
              </label>
              <label className="text-sm">
                Mått
                <select
                  disabled={!!group}
                  value={metric}
                  onChange={(e) => setMetric(e.target.value as typeof metric)}
                  className={control}
                >
                  <option value="new">Nyanmälda platser</option>
                  <option value="remaining">Kvarstående platser</option>
                </select>
              </label>
              <label className="text-sm">
                Anställningens varaktighet
                <select
                  disabled={!!group}
                  value={group ? "source" : duration}
                  onChange={(e) => setDuration(e.target.value as typeof duration)}
                  className={control}
                >
                  {group && <option value="source">Yrkesfilens avgränsning (KVAR)</option>}
                  <option value="all">Alla varaktigheter</option>
                  <option value="10">Mer än 10 dagar</option>
                </select>
              </label>
              <label className="text-sm">
                Referensmånad
                <select
                  value={period}
                  onChange={(e) => setPeriod(e.target.value)}
                  className={control}
                >
                  {[...catalog.dimensions.totals.periods].reverse().map((p) => (
                    <option key={p}>{p}</option>
                  ))}
                </select>
              </label>
              <label className="text-sm">
                Visa historik
                <select
                  value={years}
                  onChange={(e) => setYears(e.target.value)}
                  className={control}
                >
                  <option value="5">Senaste 5 åren</option>
                  <option value="10">Senaste 10 åren</option>
                  <option value="all">Hela tillgängliga perioden</option>
                </select>
              </label>
            </div>
            {group && (
              <p className="mt-4 text-sm text-ink-muted">
                Yrkesgrupper finns från {catalog.dimensions.groups.start} och har endast måttet
                kvarstående platser (källfält KVAR). Varaktigheten går inte att välja i yrkesfilen.
                Yrkesfilen är ett separat underlag och har ingen uppgift om nyanmälda platser.
              </p>
            )}
            <nav
              aria-label="Sidans figurer"
              className="mt-6 space-y-3 border-t border-border pt-5 text-sm text-brand-dark"
            >
              {[
                ["utveckling", "Utveckling över tid"],
                ["yrken", "Yrken och förändring"],
                ["geografi", "Geografisk fördelning"],
                ["sasong", "Säsongsmönster"],
                ["lor", "SCB:s arbetsgivarundersökning"],
                ["efterfragan-definitioner", "Källor och definitioner"],
              ].map(([id, label]) => (
                <a className="block underline underline-offset-4" key={id} href={`#${id}`}>
                  {label}
                </a>
              ))}
            </nav>
          </aside>
          <div className="min-w-0 space-y-10">
            {query.isError ? (
              <p role="alert" className="rounded-xl border border-border p-6">
                Statistiken kunde inte läsas.{" "}
                <button className="underline" onClick={() => void query.refetch()}>
                  Försök igen
                </button>
              </p>
            ) : query.isPending ? (
              <p role="status" className="p-8">
                Läser arbetskraftsefterfrågan…
              </p>
            ) : (
              <>
                {!currentPeriod && (
                  <p role="status" className="rounded-lg border border-border bg-muted p-5">
                    Det valda yrkesurvalet saknar uppgifter för {period}. Välj en månad från{" "}
                    {sourceStart}.
                  </p>
                )}
                {national.isError && (
                  <p role="alert">
                    Riksjämförelsen kunde inte läsas.{" "}
                    <button className="underline" onClick={() => void national.refetch()}>
                      Försök igen
                    </button>
                  </p>
                )}
                <Figure
                  id="utveckling"
                  title="Hur har efterfrågan på arbetskraft förändrats?"
                  intro={`${name} · ${description}. ${metricDefinition} ${group ? "Yrkesfilens avgränsning (KVAR); ingen valbar varaktighet." : duration === "10" ? "Varaktighet mer än 10 dagar." : "Alla varaktigheter."}`}
                  period={`${sourceStart}–${period}`}
                >
                  <label className="mb-5 flex items-start gap-3 text-sm">
                    <input
                      className="mt-1"
                      type="checkbox"
                      checked={rolling}
                      onChange={(e) => setRolling(e.target.checked)}
                    />
                    <span>
                      {metric === "new"
                        ? "Visa rullande summa för tolv månader"
                        : "Visa rullande tolvmånadersmedel"}
                    </span>
                  </label>
                  <DemandTimeChart rows={chartRows} name={name} unit={unit} />
                  <p className="mt-4 text-sm text-ink-muted">
                    {rolling
                      ? `${metric === "new" ? "Summa av tolv månaders inflöden; samma tjänst kan ha annonserats flera gånger." : "Medel av tolv månaders kvarstående platser. Ett jobb kan ingå vid flera månadsslut."} Kräver tolv sammanhängande månader med kända värden.`
                      : "Månadsvärden utan säsongsrensning."}{" "}
                    Luckor sammanbinds inte.
                  </p>
                </Figure>
                <Figure
                  id="yrken"
                  title="Inom vilka yrkesområden ökar eller minskar efterfrågan?"
                  intro={`${name} · ${metricName} · ${group || duration === "all" ? "Alla varaktigheter" : "Mer än 10 dagar"}. Välj ett område för att följa dess utveckling.`}
                  period={period}
                >
                  {group && (
                    <p className="mb-5 text-sm text-ink-muted">
                      Här jämförs samtliga yrkesområden. Den valda SSYK-gruppen gäller tidsserien,
                      kartan och geografijämförelsen.
                    </p>
                  )}
                  <DemandRanking
                    rows={query.data?.fields ?? []}
                    onSelect={(f) => {
                      setField(f);
                      setGroup("");
                    }}
                  />
                </Figure>
                <Figure
                  id="yrkesgrupper"
                  title="Vilka yrkesgrupper har flest kvarstående platser?"
                  intro={`${name} · ${field || "Samtliga yrkesområden"}. SSYK 2012, fyrsiffrig kod. Endast kvarstående platser ur den särskilda yrkesfilen, oavsett valt mått ovanför.`}
                  period={`${period}; yrkeshistorik från ${catalog.dimensions.groups.start}`}
                >
                  <DemandRanking rows={query.data?.groups ?? []} onSelect={chooseGroup} />
                  <p className="mt-4 text-sm text-ink-muted">
                    Yrkesfilens totalsumma avviker från den långa platsserien. Summera inte de två
                    underlagen. Om en SSYK-grupp finns i flera AF-yrkesområden behålls kopplingarna
                    och områdesfiltret avgränsar gruppen.
                  </p>
                </Figure>
                <Figure
                  id="geografi"
                  title="Var finns de anmälda platserna?"
                  intro={`${metricName} · ${description} · ${group ? "Yrkesfilens avgränsning (KVAR)" : duration === "all" ? "Alla varaktigheter" : "Mer än 10 dagar"}. Jämförelsen avser antal, inte platser per invånare.`}
                  period={period}
                >
                  <div className="grid items-start gap-8 xl:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)]">
                    <div>
                      <h3 className="text-lg">Norrbottens kommuner</h3>
                      {mapQuery.isPending ? (
                        <p role="status">Läser kartvärden…</p>
                      ) : mapQuery.isError ? (
                        <p role="alert">
                          Kartvärden kunde inte läsas.{" "}
                          <button className="underline" onClick={() => void mapQuery.refetch()}>
                            Försök igen
                          </button>
                        </p>
                      ) : (
                        <MunicipalityMap
                          geo={geo}
                          onGeo={changeGeo}
                          values={Object.fromEntries(
                            (mapQuery.data ?? []).map((r) => [
                              r.code,
                              {
                                value: demandValue(r.value),
                                label: demandNumber(r.value) + " platser",
                              },
                            ]),
                          )}
                          valueDescription="antal platser"
                        />
                      )}
                    </div>
                    <div>
                      <label className="mb-5 block text-sm">
                        Jämför geografier
                        <select
                          value={level}
                          onChange={(e) => setLevel(e.target.value as typeof level)}
                          className={control}
                        >
                          <option value="kommun">Kommuner i {geos[county]?.name}</option>
                          <option value="län">Alla län</option>
                        </select>
                      </label>
                      {comparison.isPending ? (
                        <p role="status">Läser jämförelse…</p>
                      ) : comparison.isError ? (
                        <p role="alert">
                          Geografijämförelsen kunde inte läsas.{" "}
                          <button className="underline" onClick={() => void comparison.refetch()}>
                            Försök igen
                          </button>
                        </p>
                      ) : (
                        <DemandRanking rows={comparison.data ?? []} onSelect={changeGeo} />
                      )}
                    </div>
                  </div>
                </Figure>
                <Figure
                  id="sasong"
                  title="Finns det återkommande säsongsmönster?"
                  intro={`${name} · ${description} · ${metricName}. Månaderna jämförs mellan fyra år; innevarande år kan vara ofullständigt. ${group ? "Yrkesfilens avgränsning (KVAR)." : duration === "all" ? "Alla varaktigheter." : "Mer än 10 dagar."}`}
                  period={`${Number(period.slice(0, 4)) - 3}–${period}`}
                >
                  <DemandSeason rows={rows.filter((r) => r.period <= period)} period={period} />
                  <p className="mt-4 text-sm text-ink-muted">
                    Figuren visar månadsvärden, även när rullande värden valts ovanför. Liknande
                    toppar flera år kan tyda på säsong, men är ingen statistisk säsongsrensning.
                  </p>
                </Figure>
              </>
            )}
            <DemandLor
              geo={geo === "00" ? "00" : county}
              name={geo === "00" ? "Riket" : geos[county]!.name}
            />
            <section
              id="efterfragan-definitioner"
              className="scroll-mt-28 rounded-xl border border-border bg-surface p-5 md:p-7"
            >
              <h2 className="text-2xl">Vad mäter statistiken?</h2>
              <div className="mt-5 space-y-5 leading-relaxed text-ink-muted">
                <p>
                  <strong className="text-ink">AF:s anmälda platser:</strong> arbetsgivarens angivna
                  rekryteringsbehov hos Arbetsförmedlingen. En annons kan innehålla flera platser.
                  Nya platser är inflödet under månaden; kvarstående är beståndet vid månadens slut.
                  Bestånd summeras inte som unika jobb över tid. Varaktighet avser anställningen,
                  inte hur länge annonsen visas.
                </p>
                <p>
                  <strong className="text-ink">Platsannonser och annonserade tjänster:</strong> en
                  annons räknas som en publicering, medan antal tjänster är annonsens angivna antal
                  platser. JobTechs Historical Ads innehåller avpublicerade annonser, medan
                  JobSearch visar aktuella. Att enbart räkna historiska annonser skulle ge
                  ofullständiga senaste månader. Separata annonsmått visas därför inte här innan
                  historiska och aktuella annonser kan sammanföras och kontrolleras.
                </p>
                <p>
                  <strong className="text-ink">Dubbletter och återpublicering:</strong> AF:s
                  aggregat saknar annons-id, så vi kan inte identifiera samma tjänst i flera
                  annonser. AF rättade maj 2026 den 16 juni efter ett tekniskt fel med dubbla
                  registreringar. Importen använder nuvarande källfiler och kontrollerar hela
                  historiken kvartalsvis. JobTech-id kan identifiera versioner av samma annons, men
                  olika id bevisar inte olika jobb.
                </p>
                <p>
                  <strong className="text-ink">Geografi och täckning:</strong> vi använder AF:s
                  redovisade län och kommun. Riket inkluderar källans restkategori utan geografi och
                  behöver därför inte motsvara summan av kommunerna. Jobb med flera arbetsorter och
                  återpublicering kan inte granskas på individannonsnivå i aggregaten. Förändrad
                  användning av Platsbanken, bemanningsannonser och ändrad täckning kan påverka
                  tidsserien.
                </p>
                <p>
                  <strong className="text-ink">Yrken och historik:</strong> yrkesområden är
                  Arbetsförmedlingens indelning och är inte samma sak som SSYK:s ensiffriga
                  yrkesområden i LoR. SSYK 2012-koder och relationer till AF-yrkesområden bevaras.
                  Totalserien börjar {catalog.dimensions.totals.start}, yrkesområden{" "}
                  {catalog.dimensions.fields.start} och SSYK-grupper{" "}
                  {catalog.dimensions.groups.start}. Källornas olika startår och populationer
                  begränsar jämförelser.
                </p>
                <p>
                  <strong className="text-ink">Noll, sekretess och bortfall:</strong> noll visas som
                  0. Skyddade värden visas som sekretess; saknade värden som uppgift saknas.
                  Frånvarande kombinationer fylls inte med noll. SCB redovisar inte vissa osäkra
                  skattningar; de visas som uppgift saknas, inte automatiskt som sekretess.
                </p>
                <p>
                  <strong className="text-ink">SCB:s LoR:</strong> en skattning av lediga jobb i
                  hela ekonomin, med och utan annons. Den kan inte adderas till AF:s platser.
                  Osäkerhetsmarginaler och metodbrottet 2024 begränsar tolkningen. Arbetskraftsbrist
                  per yrke är ett separat mått på personal som saknas där arbete inte blir utfört.
                </p>
                <p className="text-sm">
                  <a
                    className="underline"
                    href="https://arbetsformedlingen.se/statistik/sok-statistik/forklaring-av-statistiken"
                    target="_blank"
                    rel="noreferrer"
                  >
                    AF:s definitioner
                  </a>{" "}
                  ·{" "}
                  <a
                    className="underline"
                    href="https://arbetsformedlingen.se/statistik/sok-statistik"
                    target="_blank"
                    rel="noreferrer"
                  >
                    Rättningar och publicering
                  </a>{" "}
                  ·{" "}
                  <a
                    className="underline"
                    href="https://data.jobtechdev.se/dataservice/"
                    target="_blank"
                    rel="noreferrer"
                  >
                    JobTechs datatjänster
                  </a>{" "}
                  ·{" "}
                  <a
                    className="underline"
                    href="https://www.scb.se/am0702"
                    target="_blank"
                    rel="noreferrer"
                  >
                    SCB:s LoR och dokumentation
                  </a>
                </p>
              </div>
            </section>
          </div>
        </div>
      </Section>
    </>
  );
}
