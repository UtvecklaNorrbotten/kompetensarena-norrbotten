import type { IndicatorMetadata } from "@/data/types";

const geoLevelLabels: Record<IndicatorMetadata["geoLevel"], string> = {
  riket: "Riket",
  län: "Län",
  kommun: "Kommun",
};

/** Visar källa, uppdatering, geografisk nivå och period för en indikator. */
export function MetadataList({ metadata }: { metadata: IndicatorMetadata }) {
  const entries: Array<[string, string]> = [
    ["Källa", metadata.source],
    ["Senast uppdaterad", metadata.updatedAt],
    ["Geografisk nivå", `${geoLevelLabels[metadata.geoLevel]} – ${metadata.area}`],
    ["Period", metadata.period],
  ];

  return (
    <dl className="grid gap-x-8 gap-y-4 sm:grid-cols-2">
      {entries.map(([term, value]) => (
        <div key={term}>
          <dt className="text-sm uppercase tracking-wider text-ink-muted">{term}</dt>
          <dd className="mt-1 text-ink">{value}</dd>
        </div>
      ))}
    </dl>
  );
}
