import { createFileRoute, notFound } from "@tanstack/react-router";
import { AppLink } from "@/components/layout/AppLink";
import { Section } from "@/components/layout/Section";
import { PageHeader } from "@/components/ui/PageHeader";
import { areaPath, getArea } from "@/config/areas";

export const Route = createFileRoute("/omraden/$area/")({
  loader: ({ params }) => {
    const area = getArea(params.area);
    if (!area) throw notFound();
    // Ikonkomponenten kan inte serialiseras från servern – skicka bara data.
    return { slug: area.slug, title: area.title, description: area.description, topics: area.topics };
  },
  head: ({ loaderData }) => ({
    meta: [
      { title: `${loaderData?.title ?? "Område"} – Kompetensarena Norrbotten` },
      { name: "description", content: loaderData?.description ?? "" },
    ],
  }),
  component: AreaOverview,
});

function AreaOverview() {
  const area = Route.useLoaderData();
  return (
    <>
      <Section tone="light" className="py-12 md:py-16">
        <PageHeader eyebrow="Översikt" title={area.title} intro={area.description} />
      </Section>
      <Section className="py-10">
        <p className="mb-6 text-ink-muted">Området byggs ut stegvis. Fördjupningarna nedan innehåller ännu inga resultat.</p>
        <ul className="grid gap-4 md:grid-cols-2">
          {area.topics.map((topic) => (
            <li key={topic.slug}>
              <AppLink href={areaPath(area.slug, topic.slug)} className="block rounded-lg border border-border bg-surface p-6 hover:bg-brand-light focus-visible:outline">
                <h2 className="text-xl">{topic.title}</h2>
                <p className="mt-2 text-sm text-ink-muted">Platshållare · innehåll kommer senare</p>
              </AppLink>
            </li>
          ))}
        </ul>
      </Section>
    </>
  );
}
