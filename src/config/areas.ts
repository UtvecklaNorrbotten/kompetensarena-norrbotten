import { BriefcaseBusiness, GraduationCap, Industry, MapPinned, Puzzle } from "@/components/icons";

const IndustryIcon = Industry;

const CompetenceIcon = Puzzle;

const EducationIcon = GraduationCap;

export const areas = [
  {
    slug: "yrken",
    title: "Yrken",
    icon: BriefcaseBusiness,
    description: "Yrken och kompetensbehov i Norrbotten.",
    topics: [
      { slug: "rekryteringsbehov", title: "Rekryteringsbehov" },
      { slug: "pensionsavgangar", title: "Pensionsavgångar" },
    ],
  },
  {
    slug: "branscher",
    title: "Branscher",
    icon: IndustryIcon,
    description: "Branscher och arbetsgivarnas behov.",
    topics: [
      { slug: "rekryteringsbehov", title: "Rekryteringsbehov" },
      { slug: "kompetensutveckling", title: "Kompetensutveckling" },
    ],
  },
  {
    slug: "lan-kommun",
    title: "Län/Kommun",
    icon: MapPinned,
    description: "Jämför länet och kommunerna.",
    topics: [
      { slug: "rekryteringsbehov", title: "Rekryteringsbehov" },
      { slug: "befolkningsutveckling", title: "Befolkningsutveckling" },
    ],
  },
  {
    slug: "utbildning",
    title: "Utbildning",
    icon: EducationIcon,
    description: "Högre utbildning – från ansökan och studier till examen och arbetsmarknad.",
    topics: [
      { slug: "hogskolan", title: "Högskolan" },
      { slug: "yrkesexamensprogram", title: "Yrkesexamensprogram" },
    ],
  },
  {
    slug: "kompetenser",
    title: "Kompetenser",
    icon: CompetenceIcon,
    description: "Kompetenser som efterfrågas.",
    topics: [
      { slug: "kompetensutveckling", title: "Kompetensutveckling" },
      { slug: "framtida-behov", title: "Framtida behov" },
    ],
  },
] as const;

export function getArea(slug: string) {
  return areas.find((area) => area.slug === slug);
}
export function getTopic(areaSlug: string, topicSlug: string) {
  return getArea(areaSlug)?.topics.find((topic) => topic.slug === topicSlug);
}
export const areaPath = (slug: string, topic?: string) =>
  `/omraden/${slug}${topic ? `/${topic}` : ""}`;
