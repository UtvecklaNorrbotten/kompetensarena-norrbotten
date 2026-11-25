import shapes from "@/data/norrbotten-map.json";
export function MunicipalityMap({ geo, onGeo }: { geo: string; onGeo: (geo: string) => void }) {
  return (
    <div className="mt-5">
      <p className="text-sm text-ink-muted">Välj en kommun i kartan eller i listan.</p>
      <svg
        viewBox="0 0 380 425"
        className="mt-3 w-full max-h-96"
        role="group"
        aria-label="Karta över Norrbottens 14 kommuner"
      >
        {shapes.map((shape) => (
          <g key={shape.code}>
            <path
              d={shape.path}
              fill={geo === shape.code ? "#487629" : "#e5eddf"}
              fillRule="evenodd"
              stroke="#fff"
              strokeWidth="1.3"
              role="button"
              tabIndex={0}
              aria-label={`Välj ${shape.name}`}
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
              <title>{shape.name}</title>
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
      <button
        type="button"
        onClick={() => onGeo("25")}
        aria-pressed={geo === "25"}
        className={`mt-2 w-full rounded-md border p-2 text-sm ${geo === "25" ? "border-brand bg-brand-light font-semibold" : "border-border"}`}
      >
        Visa hela Norrbottens län
      </button>
      <p className="mt-3 text-xs text-ink-muted">
        Kommungränser: okfse/sweden-geojson. Kartan visar lägen och urval, inte statistikvärden.
      </p>
    </div>
  );
}
