import { createFileRoute } from "@tanstack/react-router";
import { Section } from "@/components/layout/Section";
import { PageHeader } from "@/components/ui/PageHeader";

export const Route = createFileRoute("/ladda-ned-data")({
  head: () => ({ meta: [
    { title: "Ladda ned data – Kompetensarena Norrbotten" },
    { name: "description", content: "Information om kommande datahämtning." },
    { property: "og:title", content: "Ladda ned data – Kompetensarena Norrbotten" },
    { property: "og:description", content: "Information om kommande datahämtning." },
    { property: "og:type", content: "website" },
    { name: "twitter:card", content: "summary" },
  ] }),
  component: DownloadPage,
});

function DownloadPage() {
  return <Section tone="light" className="py-12 md:py-16"><PageHeader eyebrow="Data och metod" title="Ladda ned data" intro="Nedladdning är under uppbyggnad. Här publiceras data först när källa, villkor och skydd för små grupper har kontrollerats." /></Section>;
}
