import { BriefcaseBusiness, GraduationCap, Industry, MapPinned, Puzzle } from "@/components/icons";

const IndustryIcon = Industry;

const CompetenceIcon = Puzzle;

const EducationIcon = GraduationCap;

export const areas = [
  {
    slug: "arbetsmarknad",
    title: "Arbetsmarknad",
    icon: BriefcaseBusiness,
    description:
      "Följ sysselsättning, arbetslöshet och efterfrågan på arbetskraft i kommuner, län och riket.",
    topics: [
      { slug: "sysselsattning", title: "Sysselsättning" },
      { slug: "arbetsloshet", title: "Arbetslöshet" },
      { slug: "langtidsarbetsloshet", title: "Långtidsarbetslöshet" },
      { slug: "efterfragan-pa-arbetskraft", title: "Efterfrågan på arbetskraft" },
    ],
  },
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
    title: "Län och kommun",
    icon: MapPinned,
    description: "Utforska utbildningsflöden och jämför Norrbottens kommuner.",
    topics: [
      { slug: "utbildningsfloden", title: "Flöden in och ut" },
      { slug: "befolkningsutveckling", title: "Utveckling över tid" },
      { slug: "kommunjamforelse", title: "Jämför kommunerna" },
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
