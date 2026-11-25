import { useState } from "react";
import { countAxis } from "@/lib/education-axis";
import {
  durationText,
  durationValue,
  type DurationMeasure,
  type DurationRow,
  type DurationUnit,
} from "@/lib/af-duration";
export function DurationComparison({
  rows,
  names,
  measure,
  unit,
  title,
  onChoose,
}: {
  rows: DurationRow[];
  names: Record<string, string>;
  measure: DurationMeasure;
  unit: DurationUnit;
  title: string;
  onChoose?: (geo: string) => void;
}) {
  const [all, setAll] = useState(false);
  const sorted = [...rows].sort(
    (a, b) => (durationValue(b, measure, unit) ?? -1) - (durationValue(a, measure, unit) ?? -1),
  );
  const visible = all ? sorted : sorted.slice(0, 10);
  const max =
    unit === "share"
      ? 100
      : countAxis(
          rows.map((r) => durationValue(r, measure, unit)).filter((v): v is number => v !== null),
        ).maximum;
  return (
    <>
      {rows.length === 0 ? (
        <p className="text-ink-muted">Uppgifter saknas för detta urval.</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <caption className="sr-only">{title}</caption>
            <thead>
              <tr>
                <th scope="col" className="py-3">
                  Område / grupp
                </th>
                <th scope="col" className="px-3 text-right">
                  {unit === "share" ? "Andel av gruppens arbetslösa" : "Antal personer"}
                </th>
                <th scope="col" className="hidden w-1/3 sm:table-cell">
                  <span className="sr-only">Jämförelse, gemensam skala från noll</span>
                </th>
              </tr>
            </thead>
            <tbody>
              {visible.map((r) => {
                const value = durationValue(r, measure, unit);
                const name = names[r.geo_code] ?? r.dimension_value;
                return (
                  <tr
                    key={`${r.geo_code}-${r.dimension_type}-${r.dimension_value}`}
                    className="border-t border-border"
                  >
                    <th scope="row" className="py-3 pr-2 font-normal">
                      {onChoose ? (
                        <button
                          className="text-left text-brand-dark underline underline-offset-4"
                          onClick={() => onChoose(r.geo_code)}
                        >
                          {name}
                        </button>
                      ) : (
                        name
                      )}
                    </th>
                    <td className="px-3 text-right tabular-nums">
                      {durationText(r, measure, unit)}
                    </td>
                    <td className="hidden sm:table-cell">
                      <div className="h-3 rounded bg-brand-light">
                        {value !== null && (
                          <div
                            className="h-3 rounded bg-brand-dark"
                            style={{ width: `${(100 * value) / max}%` }}
                          />
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
      {sorted.length > 10 && (
        <button
          className="mx-auto mt-5 block text-brand-dark underline underline-offset-4"
          onClick={() => setAll((v) => !v)}
        >
          {all ? "Visa de tio högsta" : `Visa alla ${sorted.length}`}
        </button>
      )}
      {rows.some((r) => durationValue(r, measure, unit) === null) && (
        <p className="mt-4 text-sm text-ink-muted">
          Sekretessmarkerade och saknade värden visas efter de exakta värdena och ingår inte i
          rangordningen.
        </p>
      )}
    </>
  );
}
