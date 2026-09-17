import type { Indicator } from "@/data/types";
import { MetadataList } from "@/components/ui/MetadataList";
import { ExampleBadge } from "@/components/ui/ExampleBadge";
import { TimeSeriesChart } from "./TimeSeriesChart";

/**
 * Standardmönstret för hur en indikator presenteras:
 * rubrik, beskrivning, visualisering och metadata.
 * Samma panel återanvänds för kommande indikatorer.
 */
export function IndicatorPanel({ indicator }: { indicator: Indicator }) {
  return (
    <article className="rounded-2xl border border-border bg-surface p-6 md:p-10">
      <div className="flex flex-wrap items-center gap-3">
        <h2 className="text-2xl md:text-3xl">{indicator.name}</h2>
        {indicator.metadata.isExample && <ExampleBadge />}
      </div>
      <p className="mt-4 max-w-(--container-prose) leading-relaxed text-ink">
        {indicator.description}
      </p>

      <div className="mt-8">
        <TimeSeriesChart
          data={indicator.series}
          unit={indicator.unit}
          ariaLabel={`Tidsserie för ${indicator.name}, ${indicator.metadata.period}`}
        />
      </div>

      <div className="mt-8 border-t border-border pt-6">
        <MetadataList metadata={indicator.metadata} />
      </div>
    </article>
  );
}
