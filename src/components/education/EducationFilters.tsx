import type { UkaFilters } from "@/lib/uka-view";
import { dimensionLabels } from "@/lib/uka-view";
import { ExplainedTerm } from "@/components/ui/ExplainedTerm";

const selectClass =
  "mt-2 w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-ink";
export function EducationFilters({
  universities,
  university,
  onUniversity,
  filters,
  onFilters,
  options,
  loading,
}: {
  universities: string[];
  university: string;
  onUniversity: (value: string) => void;
  filters: UkaFilters;
  onFilters: (filters: UkaFilters) => void;
  options: Record<string, string[]>;
  loading: boolean;
}) {
  return (
    <aside
      aria-label="Filter för Utbildning"
      className="rounded-xl border border-border bg-surface p-5 lg:sticky lg:top-24 lg:max-h-[calc(100vh-112px)] lg:overflow-y-auto"
    >
      <h2 className="text-lg">Filtrera sidan</h2>
      <p className="mt-2 text-sm leading-relaxed text-ink-muted">
        Välj lärosäte för hela sidan. Övriga urval gäller de mått som har uppdelningen.
      </p>
      <label className="mt-5 block text-sm font-medium">
        Lärosäte
        <select
          value={university}
          onChange={(e) => onUniversity(e.target.value)}
          className={selectClass}
          disabled={!universities.length}
        >
          {[...new Set([university, ...universities])].map((u) => (
            <option key={u}>{u}</option>
          ))}
        </select>
      </label>
      <label className="mt-5 block text-sm font-medium">
        Kön
        <select
          value={filters.gender}
          onChange={(e) => onFilters({ ...filters, gender: e.target.value })}
          className={selectClass}
        >
          <option value="Total">Samtliga</option>
          <option>Kvinnor</option>
          <option>Män</option>
        </select>
      </label>
      <details className="mt-5" open={Object.values(filters.dimensions).some(Boolean)}>
        <summary className="cursor-pointer text-sm font-semibold text-brand-dark">
          Fler filter
        </summary>
        {Object.entries(options).map(([key, values]) => (
          <div key={key} className="mt-4">
            <label htmlFor={`education-filter-${key}`} className="text-sm font-medium">
              {key === "examenskategori" ? (
                <ExplainedTerm
                  term="Examenskategori"
                  explanation="UKÄ grupperar examina i bland annat generella examina, yrkesexamina och konstnärliga examina. Grupperna beskriver olika typer av examen."
                />
              ) : (
                (dimensionLabels[key] ?? key)
              )}
            </label>
            <select
              id={`education-filter-${key}`}
              className={selectClass}
              disabled={loading}
              value={filters.dimensions[key] ?? ""}
              onChange={(e) =>
                onFilters({
                  ...filters,
                  dimensions: { ...filters.dimensions, [key]: e.target.value },
                })
              }
            >
              <option value="">Alla</option>
              {filters.dimensions[key] && !values.includes(filters.dimensions[key]!) && (
                <option value={filters.dimensions[key]}>Valet saknar data i aktuellt urval</option>
              )}
              {values.map((value) => (
                <option key={value}>{value}</option>
              ))}
            </select>
          </div>
        ))}
        {!Object.keys(options).length && (
          <p className="mt-3 text-sm text-ink-muted">
            {loading
              ? "Läser tillgängliga uppdelningar…"
              : "Inga ytterligare uppdelningar finns i urvalet."}
          </p>
        )}
      </details>
      <button
        type="button"
        onClick={() => onFilters({ gender: "Total", years: 5, dimensions: {} })}
        className="mt-6 text-sm text-brand-dark underline underline-offset-4"
      >
        Återställ urval
      </button>
    </aside>
  );
}
