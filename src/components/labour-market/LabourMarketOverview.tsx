import { Section } from "@/components/layout/Section";
import { AppLink } from "@/components/layout/AppLink";
import { PageHeader } from "@/components/ui/PageHeader";
import { getArea, areaPath } from "@/config/areas";
export function LabourMarketOverview() {
  const area = getArea("arbetsmarknad")!;
  return (
    <>
      <Section tone="light" className="py-12 md:py-16">
        <PageHeader
          eyebrow="Arbetsmarknad"
          title="Hur utvecklas arbetsmarknaden?"
          intro="Följ arbetslösheten och jämför kommuner, län och riket. Fler områden tillkommer efter hand."
        />
      </Section>
      <Section className="py-10">
        <div className="grid gap-6 md:grid-cols-2">
          {area.topics.map((t) => (
            <AppLink
              key={t.slug}
              href={areaPath(area.slug, t.slug)}
              className="rounded-xl border border-border bg-surface p-7 transition-colors hover:bg-brand-light"
            >
              <h2 className="text-2xl">{t.title}</h2>
              <p className="mt-3 text-ink-muted">
                {t.slug === "langtidsarbetsloshet"
                  ? "Hur länge är människor utan arbete och vilka grupper berörs mest?"
                  : "Hur har arbetslösheten förändrats och vilka grupper berörs mest?"}
              </p>
              <span className="mt-6 inline-block text-brand-dark underline underline-offset-4">
                Utforska statistiken
              </span>
            </AppLink>
          ))}
        </div>
      </Section>
    </>
  );
}
