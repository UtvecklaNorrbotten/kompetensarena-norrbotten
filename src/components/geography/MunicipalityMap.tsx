import { useId, type ReactNode } from "react";
import { Visualization } from "@/components/charts/Visualization";
import type { VisualizationExport } from "@/lib/visualization-export";
import shapes from "@/data/norrbotten-map.json";
export function MunicipalityMap({
  geo,
  onGeo,
  values,
  valueDescription = "andel",
  exportData,
  fullscreenFilters,
}: {
  geo: string;
  onGeo: (geo: string) => void;
  values?: Record<string, { value: number | null; label: string }>;
  valueDescription?: string;
  exportData?: VisualizationExport;
  fullscreenFilters?: ReactNode;
}) {
  const patternId = `map-missing-${useId().replaceAll(":", "")}`;
  const maximum = Math.max(1, ...shapes.map((s) => values?.[s.code]?.value ?? 0));
  const fill = (code: string) =>
    !values
      ? geo === code
        ? "#487629"
        : "#e5eddf"
      : values[code]?.value == null
        ? `url(#${patternId})`
        : `color-mix(in srgb, var(--chart-1) ${20 + (values[code]!.value! / maximum) * 80}%, white)`;
  const map = (
    <>
      <p className={exportData ? "pr-12 text-sm text-ink-muted" : "text-sm text-ink-muted"}>
        Välj en kommun i kartan eller i listan.
      </p>
      <div data-visualization-export>
        <svg
          viewBox="0 0 380 425"
          className="mt-3 w-full max-h-96"
          data-visualization-grow
          role="group"
          aria-label="Karta över Norrbottens 14 kommuner"
        >
          <defs>
            <pattern id={patternId} width="6" height="6" patternUnits="userSpaceOnUse">
              <path d="M0 6L6 0" stroke="var(--ink-muted)" strokeWidth="1" />
            </pattern>
          </defs>
          {shapes.map((shape) => (
            <g key={shape.code}>
              <path
                d={shape.path}
                fill={fill(shape.code)}
                fillRule="evenodd"
                stroke="#fff"
                strokeWidth={values && geo === shape.code ? "3" : "1.3"}
                role="button"
                tabIndex={0}
                aria-label={`Välj ${shape.name}${values ? `: ${values[shape.code]?.label ?? "Uppgift saknas"}` : ""}`}
                aria-pressed={geo === shape.code}
                className="cursor-pointer transition-colors hover:fill-[#90ad76] focus:fill-[#90ad76] focus:outline-none focus:stroke-[#193e16] focus:stroke-[3]"
                onClick={() => onGeo(shape.code)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault();
                    onGeo(shape.code);
                  }
                }}
              >
                <title>{`${shape.name}${values ? `: ${values[shape.code]?.label ?? "Uppgift saknas"}` : ""}`}</title>
              </path>
              {geo === shape.code && (
                <text
                  x={shape.x}
                  y={shape.y}
                  textAnchor="middle"
                  fontSize="19"
                  fill="white"
                  stroke="#27471c"
                  strokeWidth="3"
                  paintOrder="stroke"
                  pointerEvents="none"
                >
                  {shape.name}
                </text>
              )}
            </g>
          ))}
        </svg>
      </div>
      <button
        type="button"
        onClick={() => onGeo("25")}
        aria-pressed={geo === "25"}
        className={`mt-2 w-full rounded-md border p-2 text-sm ${geo === "25" ? "border-brand bg-brand-light font-semibold" : "border-border"}`}
      >
        Visa hela Norrbottens län
      </button>
      <p className="mt-3 text-xs text-ink-muted">
        Kommungränser: okfse/sweden-geojson.{" "}
        {values
          ? `Mörkare grönt visar högre ${valueDescription}. Skalan anpassas till urvalet. Streckat = uppgift saknas eller sekretess. Exakta värden finns vid varje kommun och i jämförelsen.`
          : "Kartan visar lägen och urval, inte statistikvärden."}
      </p>
    </>
  );
  return exportData ? (
    <Visualization
      data={exportData}
      exportReady={Object.keys(values ?? {}).length > 0}
      fullscreenFilters={fullscreenFilters}
      fullscreenHeading
      className="mt-5 [dialog[open]_&]:p-5"
    >
      {map}
    </Visualization>
  ) : (
    <div className="mt-5">{map}</div>
  );
}
