import { useEffect, useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { ArrowDown } from "lucide-react";
import { Section } from "@/components/layout/Section";
import { PageHeader } from "@/components/ui/PageHeader";
import { ExplainedTerm } from "@/components/ui/ExplainedTerm";
import { educationIndicators, educationSections } from "@/config/education";
import { getUkaEducation, getUkaUniversities } from "@/lib/aggregates.functions";
import { dimensionOptions, type UkaFilters } from "@/lib/uka-view";
import { EducationFilters } from "./EducationFilters";
import { EducationFigure } from "./EducationFigure";

const defaultUniversity = "Luleå tekniska universitet";
const initialFilters: UkaFilters = { gender: "Total", years: 5, dimensions: {} };

export function EducationPage({ initialSection = "" }: { initialSection?: string }) {
  const [university, setUniversity] = useState(defaultUniversity);
  const [filters, setFilters] = useState<UkaFilters>(initialFilters);
  const universityQuery = useQuery({
    queryKey: ["uka-universities"],
    queryFn: () => getUkaUniversities(),
    staleTime: 60 * 60 * 1000,
  });
  const dataQuery = useQuery({
    queryKey: ["uka-education", university],
    queryFn: () => getUkaEducation({ data: { university } }),
    staleTime: 5 * 60 * 1000,
  });
  const rows = dataQuery.data?.rows ?? [];
  const options = useMemo(
    () => dimensionOptions(dataQuery.data?.rows ?? [], filters.dimensions),
    [dataQuery.data, filters.dimensions],
  );

  useEffect(() => {
    if (
      universityQuery.data?.length &&
      !universityQuery.data.includes(defaultUniversity) &&
      university === defaultUniversity
    ) {
      setUniversity(universityQuery.data.includes("Riket") ? "Riket" : universityQuery.data[0]!);
    }
  }, [universityQuery.data, university]);

  useEffect(() => {
    // Även gamla länkar till de två tidigare platshållarna öppnar den kompletta sidan.
    const requested = window.location.hash.slice(1) || initialSection;
    const aliases: Record<string, string> = {
      "sokande-antagna": "yrkesexamensprogram",
      studenter: "hogskolan",
      examina: "hogskolan",
      etablering: "hogskolan",
    };
    const id = aliases[requested] ?? requested;
    if (!id || !dataQuery.isSuccess) return;
    const frame = requestAnimationFrame(() =>
      document.getElementById(id)?.scrollIntoView({ block: "start", behavior: "instant" }),
    );
    return () => cancelAnimationFrame(frame);
  }, [initialSection, dataQuery.isSuccess]);

  useEffect(() => {
    let frame = 0;
    const update = () => {
      frame = 0;
      let active = "";
      for (const section of educationSections) {
        const element = document.getElementById(section.slug);
        if (element && element.getBoundingClientRect().top <= 180) active = section.slug;
      }
      window.dispatchEvent(new CustomEvent("education-section", { detail: active }));
    };
    const schedule = () => {
      if (!frame) frame = requestAnimationFrame(update);
    };
    window.addEventListener("scroll", schedule, { passive: true });
    update();
    return () => {
      window.removeEventListener("scroll", schedule);
      cancelAnimationFrame(frame);
    };
  }, []);

  return (
    <div className="font-normal">
      <Section tone="light" className="py-9 md:py-12">
        <PageHeader
          eyebrow="Utbildning · UKÄ"
          title="Från utbildning till arbetsliv"
          intro="Utforska högre utbildning – från ansökan och studiestart till examen och etablering på arbetsmarknaden."
        />
        <p className="mt-4 max-w-3xl text-base leading-relaxed text-ink-muted">
          Uppgifterna gäller lärosäten i hela Sverige. Luleå tekniska universitet är förvalt.
          Studenter vid lärosätet kan bo och arbeta i andra delar av landet.
        </p>
        <a
          href="#hogskolan"
          className="mt-5 inline-flex items-center gap-2 text-sm font-medium text-brand-dark"
        >
          Utforska alla avsnitt <ArrowDown className="size-4" aria-hidden />
        </a>
      </Section>
      <div className="mx-auto grid max-w-(--container-content) items-start gap-6 px-4 py-8 md:px-8 lg:grid-cols-[230px_minmax(0,1fr)] lg:gap-8">
        <div className="lg:sticky lg:top-24">
          <EducationFilters
            universities={universityQuery.data ?? []}
            university={university}
            onUniversity={(value) => {
              setUniversity(value);
              setFilters((previous) => ({ ...previous, dimensions: {} }));
            }}
            filters={filters}
            onFilters={setFilters}
            options={options}
            loading={dataQuery.isFetching}
          />
          {universityQuery.isError && (
            <div role="alert" className="mt-3 text-sm">
              Lärosäteslistan kunde inte läsas.{" "}
              <button
                type="button"
                className="text-brand-dark underline"
                onClick={() => universityQuery.refetch()}
              >
                Försök igen
              </button>
            </div>
          )}
        </div>
        <div className="min-w-0 space-y-14">
          <div
            id="utbildning-oversikt"
            className="scroll-mt-28 rounded-xl border border-border bg-surface p-5"
          >
            <h2 className="text-xl">Så läser du sidan</h2>
            <p className="mt-3 text-base leading-relaxed">
              Filtren till vänster gäller sidan. Alla tillgängliga perioder visas. Växla varje figur
              från översiktens tidsserie till fördjupningens grupper i den senaste perioden. Begrepp
              med streckad understrykning går att klicka på.
            </p>
            <p className="mt-3 text-base leading-relaxed">
              <ExplainedTerm
                term="Läsår"
                explanation="Ett läsår omfattar höstterminen och följande vårtermin, till exempel 2024/25. Kalenderår avser januari–december. Terminsuppgifter märks VT (vårtermin) och HT (hösttermin). Jämför helst samma typ av period."
              />
              , terminer och kalenderår visas så som UKÄ redovisar dem. Perioderna skiljer sig
              mellan måtten.
            </p>
          </div>
          {dataQuery.isError && (
            <div role="alert" className="rounded-xl border border-border bg-surface p-6">
              <p>UKÄ-data kunde inte läsas. Inga exempelvärden visas.</p>
              <button
                className="mt-3 text-brand-dark underline"
                type="button"
                onClick={() => dataQuery.refetch()}
              >
                Försök igen
              </button>
            </div>
          )}
          {educationSections.map((section, index) => (
            <section
              key={section.slug}
              id={section.slug}
              aria-labelledby={`${section.slug}-heading`}
              className="scroll-mt-28"
            >
              <div className="mb-6 border-t border-border pt-6">
                <p className="mb-2 text-xs font-semibold uppercase tracking-wider text-ink-muted">
                  {String(index + 1).padStart(2, "0")} / 02
                </p>
                <h2 id={`${section.slug}-heading`} className="text-2xl md:text-3xl">
                  {section.title}
                </h2>
                <p className="mt-3 max-w-2xl text-base leading-relaxed text-ink-muted">
                  {section.intro}
                </p>
              </div>
              <div className="space-y-6">
                {educationIndicators
                  .filter((i) => i.section === section.slug)
                  .map((indicator) =>
                    dataQuery.isPending ? (
                      <div
                        key={indicator.id}
                        className="min-h-[450px] animate-pulse rounded-xl border border-border bg-surface p-6"
                        role="status"
                      >
                        <h3 className="text-xl">{indicator.title}</h3>
                        <p className="mt-4 text-sm text-ink-muted">Hämtar UKÄ-data…</p>
                        <div className="mt-8 h-56 rounded bg-neutral-surface" />
                      </div>
                    ) : dataQuery.isSuccess ? (
                      <EducationFigure
                        key={indicator.id}
                        indicator={indicator}
                        rows={rows}
                        university={university}
                        filters={filters}
                        fetched={
                          dataQuery.data.metadata.find((m) => m.indicator_id === indicator.id)
                            ?.hamtad_datum ?? null
                        }
                      />
                    ) : null,
                  )}
              </div>
            </section>
          ))}
          <p className="pb-6 text-sm leading-relaxed text-ink-muted">
            Källa: Universitetskanslersämbetet (UKÄ), Högskolan i siffror. Endast publicerade värden
            visas. Antal, andelar och utbildningsvolym ska tolkas var för sig; sökande, antagna och
            examinerade är inte en uppföljning av samma personer.
          </p>
        </div>
      </div>
    </div>
  );
}
