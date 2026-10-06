import { BriefcaseBusiness, createLucideIcon, MapPinned, Puzzle } from "lucide-react";

const IndustryIcon = createLucideIcon("IndustryIcon", [
  ["path", { d: "M3 21H21V3H17V12L10 8V12L3 8Z", key: "factory-outline" }],
]);

const CompetenceIcon = Puzzle;

const EducationIcon = createLucideIcon("EducationIcon", [
  ["path", { d: "M3 12C0 4 24 4 21 12", key: "cap-crown" }],
  ["path", {
    d: "M3 12H21V15H19C16 20 8 20 5 15H3ZM13.15 13.4a1.15 1.15 0 1 0-2.3 0a1.15 1.15 0 1 0 2.3 0Z",
    fill: "currentColor",
    fillRule: "evenodd",
    stroke: "none",
    key: "cap-band-and-visor",
  }],
  ["circle", { cx: "12", cy: "13.4", r: "0.38", fill: "currentColor", stroke: "none", key: "cap-cockade" }],
]);

export const areas = [
  { slug: "yrken", title: "Yrken", icon: BriefcaseBusiness, description: "Yrken och kompetensbehov i Norrbotten.", topics: [
    { slug: "rekryteringsbehov", title: "Rekryteringsbehov" },
    { slug: "pensionsavgangar", title: "Pensionsavgångar" },
  ] },
  { slug: "branscher", title: "Branscher", icon: IndustryIcon, description: "Branscher och arbetsgivarnas behov.", topics: [
    { slug: "rekryteringsbehov", title: "Rekryteringsbehov" },
    { slug: "kompetensutveckling", title: "Kompetensutveckling" },
  ] },
  { slug: "lan-kommun", title: "Län/Kommun", icon: MapPinned, description: "Jämför länet och kommunerna.", topics: [
    { slug: "rekryteringsbehov", title: "Rekryteringsbehov" },
    { slug: "befolkningsutveckling", title: "Befolkningsutveckling" },
  ] },
  { slug: "utbildning", title: "Utbildning", icon: EducationIcon, description: "Utbildningsutbud och behov.", topics: [
    { slug: "utbildningsniva", title: "Utbildningsnivå" },
    { slug: "samverkan", title: "Samverkan med utbildning" },
  ] },
  { slug: "kompetenser", title: "Kompetenser", icon: CompetenceIcon, description: "Kompetenser som efterfrågas.", topics: [
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
