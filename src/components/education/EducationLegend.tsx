import { educationGenderColor } from "@/lib/education-colors";

/** Gemensam legend för översiktens linjer och fördjupningens staplar. */
export function EducationLegend({
  items,
  hidden,
  onClick,
}: {
  items: { key: string; label: string; gender: string; lineStyle: "solid" | "dashed" | "dotted" }[];
  hidden: string[];
  onClick: (key: string, keyboard: boolean) => void;
}) {
  return (
    <div className="mb-4 flex flex-wrap gap-2" aria-label="Visa eller dölj serier">
      {items.map((item) => (
        <button
          key={item.key}
          type="button"
          title="Klicka för att visa eller dölja. Dubbelklicka för att isolera, dubbelklicka igen för att visa alla."
          aria-pressed={!hidden.includes(item.key)}
          onClick={(event) => onClick(item.key, event.detail === 0)}
          className={`rounded-md border border-border px-3 py-2 text-sm text-left ${hidden.includes(item.key) ? "opacity-50" : "font-semibold"}`}
        >
          <span
            aria-hidden
            className="mr-2 inline-block w-5 align-middle"
            style={{
              borderTopWidth: 3,
              borderTopStyle: item.lineStyle,
              borderTopColor: educationGenderColor(item.gender),
            }}
          />
          {item.label}
        </button>
      ))}
    </div>
  );
}
