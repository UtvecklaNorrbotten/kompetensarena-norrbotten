import { BriefcaseBusiness, Building2, GraduationCap, MapPinned, Shapes } from "lucide-react";

export const areas = [
  { slug: "yrken", title: "Yrken", icon: BriefcaseBusiness, description: "Yrken och kompetensbehov i Norrbotten.", topics: [
    { slug: "rekryteringsbehov", title: "Rekryteringsbehov" },
    { slug: "pensionsavgangar", title: "Pensionsavgångar" },
  ] },
  { slug: "branscher", title: "Branscher", icon: Building2, description: "Branscher och arbetsgivarnas behov.", topics: [
    { slug: "rekryteringsbehov", title: "Rekryteringsbehov" },
    { slug: "kompetensutveckling", title: "Kompetensutveckling" },
  ] },
  { slug: "lan-kommun", title: "Län/Kommun", icon: MapPinned, description: "Jämför länet och kommunerna.", topics: [
    { slug: "rekryteringsbehov", title: "Rekryteringsbehov" },
    { slug: "befolkningsutveckling", title: "Befolkningsutveckling" },
  ] },
  { slug: "utbildning", title: "Utbildning", icon: GraduationCap, description: "Utbildningsutbud och behov.", topics: [
    { slug: "utbildningsniva", title: "Utbildningsnivå" },
    { slug: "samverkan", title: "Samverkan med utbildning" },
  ] },
  { slug: "kompetenser", title: "Kompetenser", icon: Shapes, description: "Kompetenser som efterfrågas.", topics: [
    { slug: "kompetensutveckling", title: "Kompetensutveckling" },
    { slug: "framtida-behov", title: "Framtida behov" },
  ] },
] as const;

export function getArea(slug: string) {
  return areas.find((area) => area.slug === slug);
}
export function getTopic(areaSlug: string, topicSlug: string) {
  return getArea(areaSlug)?.topics.find((topic) => topic.slug === topicSlug);
}
export const areaPath = (slug: string, topic?: string) =>
  `/omraden/${slug}${topic ? `/${topic}` : ""}`;
