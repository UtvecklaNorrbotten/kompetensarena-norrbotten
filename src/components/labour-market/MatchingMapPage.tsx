import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useNavigate, useSearch } from "@tanstack/react-router";
import { Section } from "@/components/layout/Section";
import { AppLink } from "@/components/layout/AppLink";
import { PageHeader } from "@/components/ui/PageHeader";
import catalog from "@/data/matching-map/catalog.json";
import { getMatchingMap } from "@/lib/matching-map.functions";
import {
  matchingMapAssessment,
  matchingMapCategories,
  matchingMapCategory,
  sortMatchingMap,
  type MatchingMapDirection,
} from "@/lib/matching-map";

const educations: Record<string, { name: string; group: string; groupName: string }> =
  catalog.educations;
const occupations: Record<string, string> = catalog.occupations;
const educationNames = Object.fromEntries(
  Object.entries(educations).map(([code, e]) => [code, e.name]),
);
const surfaces = ["bg-brand-light", "bg-chart-3/25", "bg-chart-4/10"];
const selectClass = "mt-2 w-full rounded-md border border-border bg-surface px-3 py-2 text-base";
export function MatchingMapPage() {
  const search = useSearch({ strict: false }) as {
    direction?: MatchingMapDirection;
    code?: string;
    group?: string;
  };
  const navigate = useNavigate();
  const direction = search.direction === "occupation" ? "occupation" : "education";
  const options = direction === "education" ? educationNames : occupations;
  const groupChoices = Object.keys(educations).filter(
    (key) => educations[key]!.group === search.group,
  );
  const defaultCode = direction === "education" ? (groupChoices[0] ?? "15B") : "23430";
  const code =
    search.code && search.code in options
      ? search.code
      : defaultCode in options
        ? defaultCode
        : Object.keys(options)[0]!;
  const [expanded, setExpanded] = useState(false);
  const [includeZero, setIncludeZero] = useState(false);
  const query = useQuery({
    queryKey: ["matching-map", direction, code],
    queryFn: () => getMatchingMap({ data: { direction, code } }),
    staleTime: 3600000,
  });
  const names = direction === "education" ? occupations : educationNames;
  const shareIndex = direction === "education" ? 2 : 3;
  const sorted = sortMatchingMap(query.data ?? [], direction, names);
  const available = sorted.filter((r) => includeZero || r[shareIndex] !== 0);
  const shown = expanded ? available : available.slice(0, 10);
  const change = (nextDirection: MatchingMapDirection, nextCode: string) => {
    setExpanded(false);
    setIncludeZero(false);
    void navigate({
      to: ".",
      search: { direction: nextDirection, code: nextCode, group: "" },
      replace: true,
    });
  };
  return (
    <>
      <Section tone="light" className="py-12 md:py-16">
        <PageHeader
          eyebrow="Arbetsmarknad · Matchning"
          title="Vilka utbildningar och yrken matchar?"
          intro="Utforska SCB:s bedömning och se hur vanliga kombinationerna är i hela Sverige."
        />
      </Section>
      <Section className="py-10">
        <div className="mx-auto max-w-4xl space-y-8">
          <AppLink href="/omraden/arbetsmarknad/matchning" className="underline">
            Tillbaka till matchningsstatistiken
          </AppLink>
          <div className="grid gap-5 sm:grid-cols-[1fr_2fr]">
            <label>
              Utgå från
              <select
                className={selectClass}
                value={direction}
                onChange={(e) => change(e.target.value as MatchingMapDirection, "")}
              >
                <option value="education">Utbildning → yrken</option>
                <option value="occupation">Yrke → utbildningar</option>
              </select>
            </label>
            <label>
              {direction === "education" ? "Utbildning" : "Yrke"}
              <select
                className={selectClass}
                value={code}
                onChange={(e) => change(direction, e.target.value)}
              >
                {Object.entries(options)
                  .sort((a, b) => a[1].localeCompare(b[1], "sv"))
                  .map(([key, name]) => (
                    <option key={key} value={key}>
                      {name}
                    </option>
                  ))}
              </select>
            </label>
          </div>
          {direction === "education" && groupChoices.length > 1 && (
            <p className="text-ink-muted">
              Den valda utbildningsgruppen är uppdelad i flera utbildningar i SCB:s matchningskarta.
              Här visas {educationNames[code]}. Välj en annan utbildning i listan för att se övriga
              delar av gruppen.
            </p>
          )}
          <section className="rounded-xl border border-border bg-surface p-5 md:p-7">
            <h2 className="text-2xl">
              {direction === "education"
                ? "Vilka yrken arbetar de utbildade i? (data för hela Sverige)"
                : "Vilka utbildningar har de som arbetar i yrket? (data för hela Sverige)"}
            </h2>
            <p className="mt-4 text-ink-muted">
              {options[code]} · {catalog.year} · Anställda 20–69 år.
            </p>
            <p className="mt-2 text-sm text-ink-muted">
              {direction === "education"
                ? "Andel av anställda med vald utbildning som arbetar i respektive yrke."
                : "Andel av anställda i valt yrke som har respektive utbildning. De redovisade utbildningarna täcker inte alltid hela yrkesgruppen."}
            </p>
            <div className="my-6 flex flex-wrap gap-4 text-sm" aria-label="Färgförklaring">
              {matchingMapCategories.map((label, i) => (
                <span key={label} className="inline-flex items-center gap-2">
                  <span aria-hidden="true" className={`h-4 w-4 rounded ${surfaces[i]}`} />
                  {label}
                </span>
              ))}
            </div>
            {query.isPending ? (
              <p role="status">Läser matchningskartan…</p>
            ) : query.isError ? (
              <p role="alert">
                Matchningskartan kunde inte läsas.{" "}
                <button type="button" className="underline" onClick={() => void query.refetch()}>
                  Försök igen
                </button>
              </p>
            ) : (
              <>
                <p className="mb-4 text-sm text-ink-muted">
                  Visar {shown.length} av {available.length} kombinationer
                  {includeZero ? "." : " med positiv eller saknad andel."} Sorterat efter matchning,
                  andel och namn.
                </p>
                <ol className="space-y-3" aria-live="polite">
                  {shown.map((row) => {
                    const category = matchingMapCategory(row);
                    const name = names[row[direction === "education" ? 1 : 0]];
                    const share = row[shareIndex];
                    return (
                      <li
                        key={`${row[0]}-${row[1]}`}
                        className={`grid grid-cols-[minmax(0,1fr)_auto] items-center gap-4 rounded-lg p-4 ${surfaces[category]}`}
                      >
                        <div>
                          <span className="sr-only">{matchingMapCategories[category]}. </span>
                          <h3 className="text-lg">{name}</h3>
                          <p className="mt-1 text-sm">{matchingMapAssessment(row)}</p>
                        </div>
                        <p className="text-right text-lg tabular-nums">
                          {share === null ? (
                            <span className="text-sm">Uppgift saknas</span>
                          ) : (
                            `${(share * 100).toLocaleString("sv-SE", { minimumFractionDigits: 1, maximumFractionDigits: 1 })} %`
                          )}
                        </p>
                      </li>
                    );
                  })}
                </ol>
                {available.length === 0 && (
                  <p>
                    Inga kombinationer med positiv eller saknad andel. Välj ”Visa alla” för att även
                    visa nollandelar.
                  </p>
                )}
                <div className="mt-6 flex justify-center">
                  {(available.length > 10 ||
                    sorted.length > available.length ||
                    expanded ||
                    available.length === 0) && (
                    <button
                      type="button"
                      className="rounded-md border border-border px-4 py-2"
                      aria-expanded={expanded}
                      onClick={() => {
                        setExpanded(!expanded);
                        setIncludeZero(false);
                      }}
                    >
                      {expanded ? "Visa topp 10" : `Visa alla (${available.length})`}
                    </button>
                  )}
                </div>
                {expanded && (
                  <label className="mt-5 flex items-center justify-center gap-3">
                    <input
                      type="checkbox"
                      checked={includeZero}
                      onChange={(e) => setIncludeZero(e.target.checked)}
                    />
                    Visa även kombinationer med 0 % (
                    {sorted.filter((r) => r[shareIndex] === 0).length})
                  </label>
                )}
              </>
            )}
          </section>
          <section className="space-y-4 rounded-xl border border-border p-6">
            <h2 className="text-2xl">Hur ska matchningskartan läsas?</h2>
            <p>
              Andelarna avser hela Sverige år {catalog.year}. Bedömningarna bygger på Trender och
              prognoser {catalog.assessmentYear}. Matchning beskriver utbildningens inriktning och
              nivå i förhållande till yrket, inte en persons samlade kompetens eller efterfrågan på
              arbetskraft.
            </p>
            <p>
              Helt matchad innebär rätt inriktning och nivå. Delvis matchad innebär helt rätt
              inriktning med för hög eller låg nivå, eller delvis rätt inriktning oavsett nivå. Inte
              matchad innebär att inriktningen inte stämmer med yrket.
            </p>
            <p>
              Utbildningsgrupper och yrkesgrupper följer SCB:s indelning i matchningskartan.
              Andelarna behålls som SCB publicerat dem och räknas inte om till 100 procent. En
              kombination med 0 procent kan fortfarande ha en matchningsbedömning. Saknad uppgift
              visas separat från noll.
            </p>
            <p className="flex flex-wrap gap-x-5 gap-y-2">
              <a className="underline" href={catalog.workbook} target="_blank" rel="noreferrer">
                SCB:s matchningskarta (Excel)
              </a>
              <a className="underline" href={catalog.source} target="_blank" rel="noreferrer">
                SCB:s regionala matchningsindikatorer
              </a>
            </p>
          </section>
        </div>
      </Section>
    </>
  );
}
