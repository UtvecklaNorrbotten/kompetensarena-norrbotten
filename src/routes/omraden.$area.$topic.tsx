import { LongTermUnemploymentPage } from "@/components/labour-market/LongTermUnemploymentPage";
import { GeographyPage } from "@/components/geography/GeographyPage";
import { geoSearchSchema } from "@/config/geo";
import { EducationPage } from "@/components/education/EducationPage";
import { createFileRoute, notFound } from "@tanstack/react-router";
import { AppLink } from "@/components/layout/AppLink";
import { Section } from "@/components/layout/Section";
import { PageHeader } from "@/components/ui/PageHeader";
import { areaPath, getArea, getTopic } from "@/config/areas";

export const Route = createFileRoute("/omraden/$area/$topic")({
  validateSearch: geoSearchSchema,
  loader: ({ params }) => {
    const area = getArea(params.area);
    const topic = getTopic(params.area, params.topic);
    if (
      params.area === "utbildning" &&
      [
        "utbildningsniva",
        "samverkan",
        "sokande-antagna",
        "studenter",
        "examina",
        "etablering",
      ].includes(params.topic)
    )
      return {
        area: { slug: "utbildning", title: "Utbildning" },
        topic: { slug: params.topic, title: "Utbildning" },
      };
    if (params.area === "lan-kommun" && params.topic === "rekryteringsbehov")
      return {
        area: { slug: "lan-kommun", title: "Län och kommun" },
        topic: { slug: "utbildningsfloden", title: "Flöden in och ut" },
      };
    if (!area || !topic) throw notFound();
    // Ikonkomponenten kan inte serialiseras från servern – skicka bara data.
    return { area: { slug: area.slug, title: area.title }, topic };
  },
  head: ({ loaderData }) => ({
    meta: [
      {
        title: `${loaderData?.topic.title ?? "Fördjupning"} – ${loaderData?.area.title ?? "Kompetensarena Norrbotten"}`,
      },
      {
        name: "description",
        content:
          loaderData?.area.slug === "arbetsmarknad"
            ? "Tid utan arbete bland inskrivna arbetslösa. Historik, grupper och geografiska jämförelser med Arbetsförmedlingens statistik."
            : loaderData?.area.slug === "utbildning"
              ? "UKÄ-statistik om sökande, studenter, examina och arbetsmarknad efter examen."
              : loaderData?.area.slug === "lan-kommun"
                ? "Utbildningsflöden och kommunjämförelser i Norrbotten med SCB:s regionala matchningsindikatorer."
                : "Platshållare för en kommande fördjupning i Kompetensarena Norrbotten.",
      },
      {
        property: "og:title",
        content: `${loaderData?.topic.title ?? "Fördjupning"} – ${loaderData?.area.title ?? "Kompetensarena Norrbotten"}`,
      },
      {
        property: "og:description",
        content:
          loaderData?.area.slug === "arbetsmarknad"
            ? "Tid utan arbete bland inskrivna arbetslösa. Historik, grupper och geografiska jämförelser med Arbetsförmedlingens statistik."
            : loaderData?.area.slug === "utbildning"
              ? "UKÄ-statistik om sökande, studenter, examina och arbetsmarknad efter examen."
              : loaderData?.area.slug === "lan-kommun"
                ? "Utbildningsflöden och kommunjämförelser i Norrbotten med SCB:s regionala matchningsindikatorer."
                : "Platshållare för en kommande fördjupning i Kompetensarena Norrbotten.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: TopicPage,
});

function TopicPage() {
  const { area, topic } = Route.useLoaderData();
  if (area.slug === "arbetsmarknad" && topic.slug === "langtidsarbetsloshet")
    return <LongTermUnemploymentPage />;
  if (area.slug === "lan-kommun") return <GeographyPage initialSection={topic.slug} />;
  if (area.slug === "utbildning") return <EducationPage initialSection={topic.slug} />;
  return (
    <>
      <Section tone="light" className="py-12 md:py-16">
        <PageHeader
          eyebrow={area.title}
          title={topic.title}
          intro="Den här fördjupningen är under uppbyggnad. Inga resultat eller exempelvärden visas ännu."
        />
      </Section>
      <Section className="py-10">
        <AppLink
          href={areaPath(area.slug)}
          className="text-brand-dark underline underline-offset-4"
        >
          Tillbaka till {area.title}: översikt
        </AppLink>
      </Section>
    </>
  );
}
