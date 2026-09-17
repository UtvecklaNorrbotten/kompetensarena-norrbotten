import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

type SectionProps = {
  children: ReactNode;
  /** Bakgrundsyta enligt designsystemet. */
  tone?: "default" | "light" | "neutral" | "dark" | "surface";
  /** Smalare textbredd för löpande text. */
  width?: "content" | "prose";
  className?: string;
  id?: string;
};

const toneClasses: Record<NonNullable<SectionProps["tone"]>, string> = {
  default: "bg-background",
  light: "bg-brand-light",
  neutral: "bg-neutral-surface",
  surface: "bg-surface",
  dark: "bg-brand-dark text-white",
};

/**
 * Gemensam sektionsram: håller luft, bakgrundsytor och innehållsbredd konsekventa
 * så att nya sidor automatiskt får samma rytm.
 */
export function Section({
  children,
  tone = "default",
  width = "content",
  className,
  id,
}: SectionProps) {
  return (
    <section id={id} className={cn("py-16 md:py-24", toneClasses[tone], className)}>
      <div
        className={cn(
          "mx-auto w-full px-4 md:px-8",
          width === "prose"
            ? "max-w-(--container-prose)"
            : "max-w-(--container-content)",
        )}
      >
        {children}
      </div>
    </section>
  );
}
