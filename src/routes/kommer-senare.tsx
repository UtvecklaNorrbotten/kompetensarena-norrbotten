import { createFileRoute, Link } from "@tanstack/react-router";
import { Section } from "@/components/layout/Section";
import { PageHeader } from "@/components/ui/PageHeader";

const description =
  "Den här delen av Kompetensarena Norrbotten är under uppbyggnad och publiceras längre fram.";

export const Route = createFileRoute("/kommer-senare")({
  head: () => ({
    meta: [
      { title: "Under uppbyggnad – Kompetensarena Norrbotten" },
      { name: "description", content: description },
      { property: "og:title", content: "Under uppbyggnad – Kompetensarena Norrbotten" },
      { property: "og:description", content: description },
    ],
  }),
  component: KommerSenare,
});

function KommerSenare() {
  return (
    <Section tone="light" className="py-20 md:py-28">
      <PageHeader
        eyebrow="Under uppbyggnad"
        title="Den här sidan finns ännu inte"
        intro="Menyns rubriker är tillfälliga exempel. Innehållet byggs upp steg för steg när informationsstrukturen är fastställd."
      />
      <Link
        to="/"
        className="mt-8 inline-flex rounded-lg bg-brand-dark px-5 py-3 text-white transition-colors hover:bg-brand-dark/90"
      >
        Till startsidan
      </Link>
    </Section>
  );
}
