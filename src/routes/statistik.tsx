import { createFileRoute } from "@tanstack/react-router";
import { Section } from "@/components/layout/Section";
import { PageHeader } from "@/components/ui/PageHeader";
import { IndicatorPanel } from "@/components/charts/IndicatorPanel";
import { listIndicators } from "@/lib/indicators";

const description =
  "Exempel på hur statistik och indikatorer presenteras i Kompetensarena Norrbotten, med diagram och metadata.";

export const Route = createFileRoute("/statistik")({
  loader: () => listIndicators(),
  head: () => ({
    meta: [
      { title: "Statistik – Kompetensarena Norrbotten" },
      { name: "description", content: description },
      { property: "og:title", content: "Statistik – Kompetensarena Norrbotten" },
      { property: "og:description", content: description },
    ],
  }),
  component: StatistikSidan,
});

function StatistikSidan() {
  const indicators = Route.useLoaderData();

  return (
    <>
      <Section tone="light" className="py-14 md:py-20">
        <PageHeader
          eyebrow="Statistik"
          title="Så presenteras en indikator"
          intro="Nedan visas mönstret för statistik i plattformen: rubrik, kort beskrivning, visualisering och metadata om källa, uppdatering, geografisk nivå och period. Siffrorna är påhittade exempel."
        />
      </Section>

      <Section>
        <div className="space-y-10">
          {indicators.map((indicator) => (
            <IndicatorPanel key={indicator.id} indicator={indicator} />
          ))}
        </div>
      </Section>
    </>
  );
}
