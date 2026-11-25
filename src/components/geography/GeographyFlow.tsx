import { useId } from "react";
import { flowPairs, rmiNumber, type RmiRow } from "@/lib/rmi";

/** Oberoende flöden, inte en balanserad Sankey: inga summerade in-/utflöden konstrueras. */
export function GeographyFlow({ row }: { row: RmiRow }) {
  const id = useId().replaceAll(":", "");
  const maximum = Math.max(
    1,
    ...row
      .slice(6)
      .filter((v): v is number => typeof v === "number")
      .map(Math.abs),
  );
  const width = (v: unknown) =>
    typeof v === "number" ? (Math.abs(v) / maximum) * 20 + (v === 0 ? 0 : 2) : 0;
  return (
    <div>
      <div className="mb-4 grid gap-2 text-base font-semibold md:grid-cols-[1fr_170px_1fr] md:gap-5">
        <h3 className="text-brand-dark">Till utbildningsgruppen</h3>
        <span className="hidden md:block" />
        <h3 className="hidden text-[#825600] md:block">Från utbildningsgruppen</h3>
      </div>
      <div className="relative isolate grid items-center gap-5 md:grid-cols-[1fr_170px_1fr]">
        <svg
          viewBox="0 0 1000 420"
          preserveAspectRatio="none"
          className="pointer-events-none absolute inset-0 -z-10 hidden h-full w-full md:block"
          aria-hidden="true"
        >
          <defs>
            <marker
              id={`${id}-in`}
              markerWidth="5"
              markerHeight="5"
              refX="4"
              refY="2.5"
              orient="auto"
              markerUnits="userSpaceOnUse"
            >
              <path d="M0,0L5,2.5L0,5Z" fill="#487629" />
            </marker>
            <marker
              id={`${id}-out`}
              markerWidth="5"
              markerHeight="5"
              refX="4"
              refY="2.5"
              orient="auto"
              markerUnits="userSpaceOnUse"
            >
              <path d="M0,0L5,2.5L0,5Z" fill="#bc8b25" />
            </marker>
          </defs>
          {flowPairs.map((pair, i) => {
            const y = 70 + i * 140;
            return (
              <g key={pair.label}>
                <path
                  d={`M280,${y} C360,${y} 365,210 450,210`}
                  fill="none"
                  stroke="#487629"
                  strokeOpacity=".55"
                  strokeWidth={width(row[pair.incoming])}
                  markerEnd={`url(#${id}-in)`}
                />
                <path
                  d={`M550,210 C635,210 640,${y} 720,${y}`}
                  fill="none"
                  stroke="#bc8b25"
                  strokeOpacity=".55"
                  strokeWidth={width(row[pair.outgoing])}
                  markerEnd={`url(#${id}-out)`}
                />
              </g>
            );
          })}
        </svg>
        <div className="grid gap-4 md:min-h-[420px] md:grid-rows-3">
          {flowPairs.map((pair) => (
            <FlowValue
              key={pair.label}
              label={pair.inLabel}
              value={row[pair.incoming]}
              incoming
              maximum={maximum}
            />
          ))}
        </div>
        <div className="rounded-xl border border-brand bg-surface px-4 py-6 text-center shadow-sm">
          <p className="text-sm text-ink-muted">Personer {row[2].slice(0, 4)}</p>
          <p className="mt-1 mb-5 text-lg tabular-nums">{rmiNumber(row[3])}</p>
          <p className="text-sm text-ink-muted">Personer i gruppen {row[2].slice(-4)}</p>
          <p className="mt-2 text-2xl font-semibold tabular-nums text-brand-dark">
            {rmiNumber(row[4])}
          </p>
          <div className="mt-5 border-t border-border pt-4">
            <p className="text-sm text-ink-muted">SCB:s nettoförändring</p>
            <p className="mt-1 text-xl tabular-nums">
              {typeof row[5] === "number" && row[5] > 0 ? "+" : ""}
              {rmiNumber(row[5])}
            </p>
            <p className="mt-2 text-sm text-ink-muted">Ett separat mått för hela förändringen.</p>
          </div>
        </div>
        <div className="grid gap-4 md:min-h-[420px] md:grid-rows-3">
          <h3 className="text-base font-semibold text-[#825600] md:hidden">
            Från utbildningsgruppen
          </h3>
          {flowPairs.map((pair) => (
            <FlowValue
              key={pair.label}
              label={pair.outLabel}
              value={row[pair.outgoing]}
              incoming={false}
              maximum={maximum}
            />
          ))}
        </div>
      </div>
      <div className="mt-6 rounded-lg bg-neutral-surface p-4 text-sm leading-relaxed text-ink-muted">
        <p>
          Flödena läses var för sig. Samma person kan ingå i flera flöden, så de kan inte läggas
          ihop till ett totalt inflöde, utflöde eller netto. SCB:s netto i mitten visar hur hela
          gruppen har förändrats.
        </p>
        <p className="mt-2">
          Bredare band visar större flöden, med samma skala på båda sidor. Saknade uppgifter saknar
          band. Utflöden visas som antal personer; originalens minustecken finns kvar i datatabellen
          och CSV-filen. Utflyttade omfattar även avlidna.
        </p>
      </div>
    </div>
  );
}
function FlowValue({
  label,
  value,
  incoming,
  maximum,
}: {
  label: string;
  value: number | null;
  incoming: boolean;
  maximum: number;
}) {
  return (
    <div
      className={`flex min-w-0 flex-col justify-center rounded-lg border bg-surface p-4 ${incoming ? "border-[#d3e3c9]" : "border-[#eddfb9]"}`}
    >
      <p className="text-sm leading-snug text-ink-muted">{label}</p>
      <p
        className={`mt-2 text-xl font-semibold tabular-nums ${incoming ? "text-brand-dark" : "text-[#825600]"}`}
      >
        {rmiNumber(value === null ? null : Math.abs(value))}
      </p>
      <div className="mt-3 h-1.5 rounded bg-neutral-surface" aria-hidden="true">
        {value !== null && (
          <div
            className={`h-full rounded ${incoming ? "bg-[#487629]" : "bg-[#F5C55C]"}`}
            style={{ width: `${(Math.abs(value) / maximum) * 100}%` }}
          />
        )}
      </div>
    </div>
  );
}
