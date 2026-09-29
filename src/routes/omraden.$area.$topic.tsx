import { createFileRoute, notFound } from "@tanstack/react-router";
import { AppLink } from "@/components/layout/AppLink";
import { Section } from "@/components/layout/Section";
import { PageHeader } from "@/components/ui/PageHeader";
import { areaPath, getArea, getTopic } from "@/config/areas";

export const Route = createFileRoute("/omraden/$area/$topic")({
  loader: ({ params }) => {
    const area = getArea(params.area);
    const topic = getTopic(params.area, params.topic);
    if (!area || !topic) throw notFound();
    // Ikonkomponenten kan inte serialiseras från servern – skicka bara data.
    return { area: { slug: area.slug, title: area.title }, topic };
  },
  head: ({ loaderData }) => ({
    meta: [
      { title: `${loaderData?.topic.title ?? "Fördjupning"} – ${loaderData?.area.title ?? "Kompetensarena Norrbotten"}` },
      { name: "description", content: "Platshållare för en kommande fördjupning i Kompetensarena Norrbotten." },
    ],
  }),
  component: TopicPage,
});

function TopicPage() {
  const { area, topic } = Route.useLoaderData();
  return (
    <>
      <Section tone="light" className="py-12 md:py-16">
        <PageHeader eyebrow={area.title} title={topic.title} intro="Den här fördjupningen är under uppbyggnad. Inga resultat eller exempelvärden visas ännu." />
      </Section>
      <Section className="py-10">
        <AppLink href={areaPath(area.slug)} className="text-brand-dark underline underline-offset-4">Tillbaka till {area.title}: översikt</AppLink>
      </Section>
    </>
  );
}
