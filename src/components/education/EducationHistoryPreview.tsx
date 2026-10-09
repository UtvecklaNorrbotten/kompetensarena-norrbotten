import { Root, Anchor, Content, Portal, Close } from "@radix-ui/react-popover";
import { X } from "lucide-react";
import { Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { educationGenderColor } from "@/lib/education-colors";
import { formatUkaValue, ukaGenderSeries, ukaGenderTimeline, type UkaRow } from "@/lib/uka-view";

/** Ett litet smakprov vid klickpunkten, utan sidopanel eller fullständiga axelrubriker. */
export function EducationHistoryPreview({
  rows,
  category,
  unit,
  x,
  y,
  onClose,
}: {
  rows: UkaRow[];
  category: string;
  unit: string;
  x: number;
  y: number;
  onClose: () => void;
}) {
  const genders = ukaGenderSeries(rows);
  const data = ukaGenderTimeline(rows, genders);
  return (
    <Root
      open
      onOpenChange={(open) => {
        if (!open) onClose();
      }}
    >
      <Anchor style={{ position: "fixed", left: x, top: y, width: 0, height: 0 }} />
      <Portal>
        <Content
          side="right"
          align="start"
          sideOffset={12}
          collisionPadding={8}
          onOpenAutoFocus={(event) => event.preventDefault()}
          onCloseAutoFocus={(event) => event.preventDefault()}
          aria-label={`Historik för ${category.replaceAll("|", " · ") || "Samtliga"}`}
          className="z-50 rounded-lg border border-border bg-surface p-3 text-ink shadow-lg"
          style={{ width: 320, maxWidth: "calc(100vw - 16px)" }}
        >
          <div className="flex items-center justify-between gap-2">
            <p className="truncate text-sm font-medium" title={category.replaceAll("|", " · ")}>
              {category.replaceAll("|", " · ") || "Samtliga"}
            </p>
            <Close
              className="shrink-0 rounded p-1 hover:bg-neutral-surface"
              aria-label="Stäng historik"
            >
              <X className="size-4" aria-hidden />
            </Close>
          </div>
          <div className="mt-2 h-36 w-full">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={data} margin={{ top: 8, right: 6, bottom: 8, left: 6 }}>
                <XAxis dataKey="period" hide />
                <YAxis hide domain={unit === "%" ? [0, 100] : [0, "auto"]} />
                <Tooltip
                  isAnimationActive={false}
                  formatter={(value: number, name: string) => [formatUkaValue(value, unit), name]}
                  contentStyle={{
                    background: "var(--surface)",
                    border: "1px solid var(--border)",
                    borderRadius: "var(--radius)",
                    fontSize: 12,
                  }}
                />
                {genders.map((gender) => (
                  <Line
                    key={gender}
                    dataKey={gender}
                    name={gender === "Total" ? "Samtliga" : gender}
                    stroke={educationGenderColor(gender)}
                    strokeWidth={2}
                    strokeDasharray={gender === "Män" ? "5 3" : undefined}
                    dot={{ r: 2 }}
                    activeDot={{ r: 3 }}
                    connectNulls={false}
                    isAnimationActive={false}
                  />
                ))}
              </LineChart>
            </ResponsiveContainer>
          </div>
          <div className="flex justify-between text-xs text-ink-muted">
            <span>{data[0]?.["period"]}</span>
            <span>{data.at(-1)?.["period"]}</span>
          </div>
          <div className="mt-2 flex flex-wrap gap-x-3 gap-y-1 text-xs">
            {genders.map((gender) => (
              <span key={gender} className="inline-flex items-center gap-1">
                <span
                  className="size-2 rounded-sm"
                  style={{ background: educationGenderColor(gender) }}
                  aria-hidden
                />
                {gender === "Total" ? "Samtliga" : gender}
              </span>
            ))}
          </div>
        </Content>
      </Portal>
    </Root>
  );
}
