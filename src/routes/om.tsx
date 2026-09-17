import { createFileRoute } from "@tanstack/react-router";
import { Section } from "@/components/layout/Section";
import { PageHeader } from "@/components/ui/PageHeader";
import { site } from "@/config/site";

const description =
  "Om Kompetensarena Norrbotten – uppdrag, samverkan och kontakt. Sidan visar webbplatsens typografi och textlayout.";

export const Route = createFileRoute("/om")({
  head: () => ({
    meta: [
      { title: "Om Kompetensarena Norrbotten" },
      { name: "description", content: description },
      { property: "og:title", content: "Om Kompetensarena Norrbotten" },
      { property: "og:description", content: description },
    ],
  }),
  component: OmSidan,
});

function OmSidan() {
  return (
    <>
      <Section tone="light" className="py-14 md:py-20">
        <PageHeader
          eyebrow={site.owner}
          title="Om Kompetensarena Norrbotten"
          intro="Kompetensarena Norrbotten är en samverkansplattform för kompetensförsörjning i länet. Texterna nedan är kortfattade exempel och ska ersättas med verkligt innehåll."
        />
      </Section>

      <Section width="prose">
        <h2 className="text-2xl">Uppdrag</h2>
        <p className="mt-4 leading-relaxed">
          Uppdraget är att stärka regionens förmåga att möta behovet av kompetens i en
          tid av stora industriella investeringar och demografiska förändringar. Arbetet
          sker i bred samverkan mellan näringsliv, utbildningsaktörer och offentlig
          sektor.
        </p>

        <h2 className="mt-12 text-2xl">Kunskaps- och analysportal</h2>
        <p className="mt-4 leading-relaxed">
          Webbplatsen ska på sikt samla statistik, indikatorer, kartor och analyser om
          kompetensförsörjning i Norrbotten. Utvecklingen sker stegvis. Den här versionen
          innehåller webbplatsens grundläggande struktur, grafiska profil och ett enkelt
          exempel på hur statistik kommer att presenteras.
        </p>

        <h2 className="mt-12 text-2xl">Kontakt</h2>
        <p className="mt-4 leading-relaxed">
          Frågor om plattformen skickas till{" "}
          <a
            href={`mailto:${site.contactEmail}`}
            className="text-brand-dark underline underline-offset-4 hover:no-underline"
          >
            {site.contactEmail}
          </a>
          .
        </p>
      </Section>
    </>
  );
}
