import { BriefcaseBusiness, createLucideIcon, MapPinned, Puzzle } from "lucide-react";

const IndustryIcon = createLucideIcon("IndustryIcon", [
  ["path", { d: "M3 21H21V3H17V12L10 8V12L3 8Z", key: "factory-outline" }],
]);

const CompetenceIcon = Puzzle;

// Svensk studentmössa i profil, ren linjestil: mjuk kulle, band, kokard och böjd skärm.
const EducationIcon = createLucideIcon("EducationIcon", [
  ["path", { d: "M5 11C5 7.5 8 5.5 12 5.5s7 2 7 5.5", key: "cap-crown" }],
  ["rect", { x: "3.5", y: "11", width: "17", height: "3.4", rx: "1.2", key: "cap-band" }],
  ["circle", { cx: "12", cy: "12.7", r: "1.1", fill: "none", key: "cap-cockade" }],
  ["path", { d: "M4 14.4C2.6 15 2.4 16.3 4.2 16.6c2.3.4 5.3.4 7.8.4", key: "cap-visor" }],
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
