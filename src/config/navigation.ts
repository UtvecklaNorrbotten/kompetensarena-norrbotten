/**
 * PLACEHOLDER-NAVIGATION
 * ----------------------
 * Informationsarkitekturen är inte fastställd. Rubriker och poster nedan är
 * exempel och ska bytas ut. Navigationskomponenterna läser enbart denna fil —
 * ingen menytext finns i komponentkoden.
 *
 * `href` som pekar på en sida som ännu inte finns sätts till "/kommer-senare".
 */

export type NavItem = {
  label: string;
  href: string;
  description?: string;
};

export type NavGroup = {
  label: string;
  href: string;
  items?: NavItem[];
};

export const mainNavigation: NavGroup[] = [
  {
    label: "Statistik",
    href: "/statistik",
    items: [
      {
        label: "Exempelindikator",
        href: "/statistik",
        description: "Visar hur en indikator presenteras med metadata.",
      },
      {
        label: "Arbetsmarknad",
        href: "/kommer-senare",
        description: "Placeholder – innehåll tillkommer.",
      },
      {
        label: "Utbildning",
        href: "/kommer-senare",
        description: "Placeholder – innehåll tillkommer.",
      },
    ],
  },
  {
    label: "Analyser",
    href: "/kommer-senare",
    items: [
      {
        label: "Fördjupningar",
        href: "/kommer-senare",
        description: "Placeholder – innehåll tillkommer.",
      },
      {
        label: "Utveckling över tid",
        href: "/kommer-senare",
        description: "Placeholder – innehåll tillkommer.",
      },
    ],
  },
  {
    label: "Om Kompetensarena",
    href: "/om",
    items: [
      { label: "Uppdrag och samverkan", href: "/om" },
      { label: "Kontakt", href: "/om" },
    ],
  },
];
