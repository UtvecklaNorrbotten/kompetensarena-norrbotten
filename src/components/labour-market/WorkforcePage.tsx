import { Select, Figure } from "./WorkforceControls";
import { EducationBackground } from "./WorkforceEducation";
import { useState } from "react";
import { useNavigate, useSearch } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import snapshot from "@/data/workforce/catalog.json";
import { DEFAULT_GEO_CODE } from "@/config/geo";
import { getWorkforceSlice, getWorkforceComparison } from "@/lib/aggregates.functions";
import {
  workforcePoint,
  workforceValue,
  workforceChange,
  workforceSegment,
  type WorkforceCatalog,
} from "@/lib/workforce";
import { employmentNumber } from "@/lib/employment";
import { Section } from "@/components/layout/Section";
import { PageHeader } from "@/components/ui/PageHeader";
import { MunicipalityMap } from "@/components/geography/MunicipalityMap";
import { EmploymentChart } from "./EmploymentCharts";
import { WorkforcePyramid } from "./WorkforcePyramid";
const catalog = snapshot as WorkforceCatalog;
export function WorkforcePage() {
  const search = useSearch({ strict: false }) as { geo?: string };
  const navigate = useNavigate();
  const geo = search.geo && search.geo in catalog.geographies ? search.geo : DEFAULT_GEO_CODE;
  const [dataset, setDataset] = useState("status-month");
  const info = catalog.datasets[dataset]!;
  const [selectedSex, setSex] = useState("1+2");
  const sex = info.sexes.includes(selectedSex)
    ? selectedSex
    : info.sexes.includes("totalt")
      ? "totalt"
      : info.sexes[0]!;
  const [educationFamily, setEducationFamily] = useState("grupp");
  const visibleCategories = Object.entries(info.categories).filter(
    ([c]) => !info.groups || info.groups[educationFamily]?.includes(c),
  );
  const [selectedCategory, setCategory] = useState("");
  const category = visibleCategories.some(([c]) => c === selectedCategory)
    ? selectedCategory
    : info.group === "Alder"
      ? "20-64"
      : info.group === "Fodelseregion"
        ? "tot"
        : visibleCategories[0]![0];
  const [selectedAge, setAge] = useState("60-64");
  const age =
    info.group === "Alder"
      ? category
      : selectedAge in info.ages
        ? selectedAge
        : ((dataset === "industry-age" ? "55-64" : Object.keys(info.ages)[0]) ?? "");
  const [selectedMeasure, setMeasure] = useState("");
  const measure =
    selectedMeasure in info.measures
      ? selectedMeasure
      : (Object.entries(info.measures).find(([, l]) => l.includes("(arbetskraften)"))?.[0] ??
        Object.keys(info.measures)[0]!);
  const [selectedPeriod, setPeriod] = useState("");
  const period = info.periods.includes(selectedPeriod) ? selectedPeriod : info.periods.at(-1)!;
  const [showAll, setShowAll] = useState(false);
  const [level, setLevel] = useState("kommun");
  const county = geo === "00" ? DEFAULT_GEO_CODE : geo.slice(0, 2);
  const localAvailable = `${dataset}/geo-${geo}.json` in catalog.files;
  const effectiveGeo = localAvailable
    ? geo
    : `${dataset}/geo-${county}.json` in catalog.files
      ? county
      : "00";
  const name = catalog.geographies[effectiveGeo]!;
  const sexName = sex === "1" ? "Män" : sex === "2" ? "Kvinnor" : "Samtliga kön";
  const unit =
    info.units[measure]?.base === "procent" ||
    info.measures[measure]!.includes("procent") ||
    ["arbetslöshet", "arbetskraftsdeltagande", "sysselsättningsgrad"].includes(
      info.measures[measure]!,
    )
      ? "%"
      : "personer";
  const decimals = unit === "%" ? 1 : 0;
  const changeGeo = (value: string) =>
    void navigate({
      to: ".",
      search: (previous: Record<string, unknown>) => ({ ...previous, geo: value }),
      replace: true,
    });
  const query = useQuery({
    queryKey: ["workforce", dataset, effectiveGeo],
    queryFn: () => getWorkforceSlice({ data: { dataset, geo: effectiveGeo } }),
    staleTime: 3600000,
  });
  const national = useQuery({
    queryKey: ["workforce", dataset, "00"],
    queryFn: () => getWorkforceSlice({ data: { dataset, geo: "00" } }),
    staleTime: 3600000,
  });
  const comparison = useQuery({
    queryKey: ["workforce-comparison", dataset, period, sex, category, age, measure],
    queryFn: () =>
      getWorkforceComparison({ data: { dataset, period, sex, category, age, measure } }),
    staleTime: 3600000,
  });
  const rows = query.data ?? [];
  const point = workforcePoint(rows, period, sex, category, age, measure);
  const value = workforceValue(point);
  const change = workforceChange(rows, period, sex, category, age, measure, info);
  const series = info.periods
    .filter((p) => p <= period)
    .map((p) => {
      const row = workforcePoint(rows, p, sex, category, age, measure);
      const other = workforcePoint(national.data ?? [], p, sex, category, age, measure);
      return {
        label: p.replace("M", "-"),
        value: workforceValue(row),
        status: row?.[6] ?? "",
        other: effectiveGeo === "00" ? null : workforceValue(other),
        otherStatus: other?.[6] ?? "",
        segment: workforceSegment(info.table, p),
      };
    });
  const categories = visibleCategories
    .filter(([c]) => !["00I", "00N", "00S", "TOTAL"].includes(c))
    .map(([code, label]) => {
      const r = workforcePoint(
        rows,
        period,
        sex,
        code,
        info.group === "Alder" ? code : age,
        measure,
      );
      return { label, value: workforceValue(r), status: r?.[6] ?? "" };
    })
    .sort((a, b) => (b.value ?? -Infinity) - (a.value ?? -Infinity));
  const ranking = (comparison.data ?? [])
    .filter((r) =>
      level === "lan"
        ? r.code.length === 2 && r.code !== "00"
        : r.code.length === 4 && r.code.startsWith(county),
    )
    .sort((a, b) => (b.value ?? -Infinity) - (a.value ?? -Infinity));
  const reference = `${name} · ${sexName}${info.table === "TAB6368" ? " · 20–64 år" : ""}${age ? ` · ${info.ages[age]}` : ""} · ${info.categories[category]} · ${info.measures[measure]}`;
  const source = `Källa: SCB, ${info.table}. ${info.label}. Referensperiod ${period.replace("M", "-")}. Uppdaterad ${info.updated.slice(0, 10)}. ${reference}.`;
  const chartProps = { unit, filename: "arbetskraft", source };
  return (
    <div className="font-normal">
      <Section tone="light" className="py-9 md:py-12">
        <PageHeader
          eyebrow="Arbetsmarknad · Arbetskraft"
          title="Hur ser arbetskraften ut?"
          intro="Följ arbetskraftens storlek, deltagande och sammansättning. Se vilka grupper som står utanför och hur åldersstrukturen varierar."
        />
        <nav
          aria-label="Sidans avsnitt"
          className="mt-6 flex flex-wrap gap-x-6 gap-y-3 text-brand-dark"
        >
          {[
            ["utveckling", "Utveckling"],
            ["grupper", "Grupper"],
            ["alder", "Åldersstruktur"],
            ["utbildning", "Arbetskraft efter utbildning"],
            ["geografi", "Jämför geografier"],
            ["definitioner", "Källor och definitioner"],
          ].map(([id, label]) => (
            <a key={id} href={`#${id}`} className="underline underline-offset-4">
              {label}
            </a>
          ))}
        </nav>
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
                setMeasure("");
                setPeriod("");
                setShowAll(false);
              }}
            >
              {Object.entries(catalog.datasets).map(([k, d]) => (
                <option key={k} value={k}>
                  {d.label}
                </option>
              ))}
            </Select>
            <Select label="Geografi" value={geo} onChange={changeGeo}>
              {["Riket", "Län", "Kommuner"].map((label, i) => (
                <optgroup key={label} label={label}>
                  {Object.entries(catalog.geographies)
                    .filter(([g]) =>
                      i === 0
                        ? g === "00"
                        : i === 1
                          ? g.length === 2 && g !== "00"
                          : g.length === 4,
                    )
                    .sort((a, b) => a[1].localeCompare(b[1], "sv"))
                    .map(([g, l]) => (
                      <option key={g} value={g}>
                        {l}
                      </option>
                    ))}
                </optgroup>
              ))}
            </Select>
            <Select label="Kön" value={sex} onChange={setSex}>
              {info.sexes.map((s) => (
                <option key={s} value={s}>
                  {s === "1" ? "Män" : s === "2" ? "Kvinnor" : "Samtliga"}
                </option>
              ))}
            </Select>
            {info.groups && (
              <Select
                label="Utbildningsindelning"
                value={educationFamily}
                onChange={(v) => {
                  setEducationFamily(v);
                  setCategory("");
                }}
              >
                <option value="grupp">Utbildningsgrupp</option>
                <option value="niva">Nivå</option>
                <option value="inriktning">Inriktning</option>
              </Select>
            )}
            <Select
              label={
                info.group === "Alder"
                  ? "Åldersgrupp"
                  : info.group === "Yrke2012"
                    ? "Yrke (SSYK 2012, tre siffror)"
                    : info.group === "SNI2007"
                      ? "Bransch"
                      : "Grupp"
              }
              value={category}
              onChange={setCategory}
            >
              {visibleCategories.map(([c, l]) => (
                <option key={c} value={c}>
                  {l}
                </option>
              ))}
            </Select>
            {info.group !== "Alder" && Object.keys(info.ages).length > 1 && (
              <Select label="Åldersgrupp" value={age} onChange={setAge}>
                {Object.entries(info.ages).map(([c, l]) => (
                  <option key={c} value={c}>
                    {l}
                  </option>
                ))}
              </Select>
            )}
            <Select label="Mått" value={measure} onChange={setMeasure}>
              {Object.entries(info.measures).map(([c, l]) => (
                <option key={c} value={c}>
                  {l}
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
            <MunicipalityMap geo={geo} onGeo={changeGeo} />
          </aside>
          <div className="min-w-0 space-y-10 md:space-y-14">
            {!localAvailable && (
              <p role="status" className="rounded-xl border border-border bg-surface p-5">
                Det valda underlaget saknar uppgifter för {catalog.geographies[geo]}. Här visas{" "}
                {name}. Övriga avsnitt anger sin egen geografi.
              </p>
            )}
            {query.isError || national.isError ? (
              <p role="alert">
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
              <p role="status">Hämtar arbetskraftsstatistik…</p>
            ) : (
              <>
                <div className="grid gap-4 sm:grid-cols-2">
                  <div className="rounded-xl border border-border bg-surface p-5">
                    <p className="text-sm text-ink-muted">
                      {info.measures[measure]} · {period.replace("M", "-")}
                    </p>
                    <p className="mt-3 text-3xl font-semibold">
                      {employmentNumber(value, point?.[6], decimals)} {value != null ? unit : ""}
                    </p>
                    <p className="mt-3 text-sm">{reference}</p>
                  </div>
                  <div className="rounded-xl border border-border bg-surface p-5">
                    <p className="text-sm text-ink-muted">
                      Förändring mot samma månad föregående år / föregående år
                    </p>
                    <p className="mt-3 text-3xl font-semibold">
                      {employmentNumber(change, "", decimals)}{" "}
                      {change != null ? (unit === "%" ? "procentenheter" : "personer") : ""}
                    </p>
                  </div>
                </div>
                <Figure
                  id="utveckling"
                  title={
                    dataset === "occupation-year"
                      ? "Hur har antalet anställda i yrket förändrats?"
                      : dataset === "retirement-education"
                        ? "Hur har gruppen sysselsatta 60–64 år förändrats?"
                        : dataset === "industry-age"
                          ? "Hur har äldre sysselsatta i branschen förändrats?"
                          : "Hur har arbetskraften och deltagandet förändrats?"
                  }
                  intro={reference}
                  source={source}
                >
                  <EmploymentChart
                    key={`${dataset}-${measure}-${category}-${age}-${sex}`}
                    rows={series}
                    name={name}
                    {...chartProps}
                  />
                  <p className="mt-5 text-sm text-ink-muted">
                    Välj arbetskraftsdeltagande för att jämföra andelen av befolkningen i samma
                    grupp. Månader är inte säsongrensade. Årsmedelvärden och registeruppgifter visas
                    i separata underlag.
                  </p>
                </Figure>
                <Figure
                  id="grupper"
                  title={
                    dataset === "occupation-year"
                      ? "Vilka yrken har flest anställda i vald åldersgrupp?"
                      : dataset === "industry-age"
                        ? "Vilka branscher har flest sysselsatta i vald åldersgrupp i riket?"
                        : dataset === "retirement-education"
                          ? unit === "%"
                            ? "Vilka utbildningsgrupper har högst andel sysselsatta 60–64 år?"
                            : info.measures[measure]!.startsWith("Samtliga")
                              ? "Vilka utbildningsgrupper har flest sysselsatta 20–64 år?"
                              : "Vilka utbildningsgrupper har flest sysselsatta 60–64 år?"
                          : "Hur skiljer sig arbetskraften mellan grupper?"
                  }
                  intro={`${name} · ${sexName} · ${info.measures[measure]}. ${info.group !== "Alder" && age ? info.ages[age] : "Åldersgrupper kan överlappa och ska inte summeras."}`}
                  source={source}
                >
                  <EmploymentChart
                    rows={showAll ? categories : categories.slice(0, 15)}
                    rank
                    name={info.measures[measure]!}
                    {...chartProps}
                  />
                  {categories.length > 15 && (
                    <button
                      className="mx-auto mt-6 block underline underline-offset-4"
                      onClick={() => setShowAll(!showAll)}
                    >
                      {showAll
                        ? "Visa de 15 största"
                        : `Visa samtliga ${categories.length} grupper`}
                    </button>
                  )}
                  {["occupation-year", "retirement-education", "industry-age"].includes(
                    dataset,
                  ) && (
                    <p className="mt-5 text-sm text-ink-muted">
                      Åldersstrukturen visar hur många som arbetar i valda åldrar. Den visar inte
                      när de slutar arbeta eller hur många som behöver ersättas. Yrkesstatistiken
                      omfattar anställda; BAS omfattar även företagare. Välj 60–64 år i
                      yrkesunderlaget eller 55–64 / 65–74 år i branschunderlaget.
                    </p>
                  )}
                </Figure>
                {dataset === "status-month" && (
                  <Figure
                    id="utanfor"
                    title="Vilka grupper står utanför arbetskraften?"
                    intro={`${name} · ${sexName} · ${info.ages[age]} · ${period.replace("M", "-")}. BAS klassificerar varje person efter arbetsmarknadsstatus.`}
                    source={source}
                  >
                    <EmploymentChart
                      rows={Object.entries(info.measures)
                        .filter(([, l]) =>
                          [
                            "antal studerande",
                            "antal pensionärer",
                            "antal sjuka",
                            "antal övriga",
                          ].includes(l),
                        )
                        .map(([c, label]) => {
                          const r = workforcePoint(rows, period, sex, category, age, c);
                          return {
                            label: label.replace("antal ", ""),
                            value: workforceValue(r),
                            status: r?.[6] ?? "",
                          };
                        })}
                      unit="personer"
                      name="Personer utanför arbetskraften"
                      filename="arbetskraft-utanfor"
                      source={source}
                      rank
                    />
                    <p className="mt-5 text-sm text-ink-muted">
                      Grupperna är inte ett mått på tillgänglig arbetskraft. Den som arbetar och
                      samtidigt studerar kan klassificeras som sysselsatt. BAS arbetslösa skiljer
                      sig från Arbetsförmedlingens inskrivna arbetslösa.
                    </p>
                  </Figure>
                )}
              </>
            )}
            <WorkforcePyramid geo={geo} />
            <EducationBackground geo={geo} />
            <Figure
              id="geografi"
              title="Hur skiljer sig arbetskraften mellan platser?"
              intro={reference}
              source={source}
            >
              <Select label="Jämför geografier" value={level} onChange={setLevel}>
                <option value="kommun">Kommuner i {catalog.geographies[county]}</option>
                <option value="lan">Alla län</option>
              </Select>
              {comparison.isPending ? (
                <p role="status" className="mt-6">
                  Hämtar jämförelse…
                </p>
              ) : comparison.isError ? (
                <p role="alert" className="mt-6">
                  Jämförelsen kunde inte läsas.{" "}
                  <button className="underline" onClick={() => void comparison.refetch()}>
                    Försök igen
                  </button>
                </p>
              ) : ranking.length ? (
                <div className="mt-6">
                  <EmploymentChart
                    rows={ranking}
                    rank
                    name={info.measures[measure]!}
                    {...chartProps}
                  />
                </div>
              ) : (
                <p className="mt-6">
                  Detta underlag har inga uppgifter på vald geografisk nivå. Välj län eller ett
                  BAS-underlag med kommunuppgifter.
                </p>
              )}
            </Figure>
            <section
              id="definitioner"
              className="scroll-mt-28 rounded-xl border border-border bg-surface p-5 md:p-8"
            >
              <h2 className="text-2xl">Vad mäter statistiken?</h2>
              <div className="mt-5 space-y-4 leading-relaxed text-ink-muted">
                <p>
                  Arbetskraften är sysselsatta och arbetslösa enligt BAS. Arbetskraftsdeltagande är
                  arbetskraftens andel av befolkningen i samma åldersgrupp, kön och geografi.
                  Andelar hämtas som publicerade mått från SCB.
                </p>
                <p>
                  BAS-månader och årsmedelvärden beskriver boende i området. RMI U1b kombinerar
                  förvärvsarbetande och inskrivna arbetslösa hos Arbetsförmedlingen och har därför
                  en annan definition än BAS. Yrkesregistret och RMI U4 beskriver personer med
                  arbetsplats i länet. Branschernas åldersuppgifter i detta underlag finns endast
                  för riket. Dessa populationer ska inte blandas.
                </p>
                <p>
                  BAS börjar 2020. Det finns ännu inte tio års jämförbar BAS-historik. RMI U4 har
                  källbyte 2022. Yrkesregistret har modellimputerade yrken och utökad åldersgräns
                  från 2023, samt förändrad företagaravgränsning 2024. Linjer och
                  förändringsberäkningar bryts vid relevanta gränser.
                </p>
                <p>
                  SCB skyddar uppgifter genom statistiska justeringar. Totaler behöver därför inte
                  motsvara summan av delarna. Saknade eller prickade värden visas som saknade,
                  aldrig som noll. Överlappande åldersgrupper och utbildningsindelningar ska inte
                  summeras.
                </p>
                <p>
                  Ålderspyramiden och arbetskraften efter utbildningsinriktning har egna,
                  uttryckligen angivna referensperioder. De följer geografin men använder egna
                  grupper och kön.
                </p>
              </div>
              <details className="mt-6">
                <summary className="cursor-pointer font-semibold">
                  Källor, täckning och SCB:s fotnoter
                </summary>
                <div className="mt-4 space-y-6">
                  {Object.entries(catalog.datasets).map(([id, d]) => (
                    <div key={id}>
                      <a className="underline" href={d.source} target="_blank" rel="noreferrer">
                        {d.label} · {d.table}
                      </a>
                      <p className="mt-2 text-sm">
                        {d.periods[0]}–{d.periods.at(-1)}. Källa uppdaterad {d.updated.slice(0, 10)}
                        .
                      </p>
                      {d.notes.map((n, i) => (
                        <p key={i} className="mt-2 whitespace-pre-line text-sm text-ink-muted">
                          {n}
                        </p>
                      ))}
                    </div>
                  ))}
                </div>
              </details>
            </section>
          </div>
        </div>
      </Section>
    </div>
  );
}
