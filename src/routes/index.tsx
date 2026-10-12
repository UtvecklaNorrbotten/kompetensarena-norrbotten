import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowRight } from "lucide-react";
import { AppLink } from "@/components/layout/AppLink";
import { Section } from "@/components/layout/Section";
import { areas, areaPath } from "@/config/areas";
import { site } from "@/config/site";

const description =
  "Kompetensarena Norrbotten kombinerar arbetsgivarnas kartlagda behov med statistik om arbetsmarknad, branscher och utbildning som stöd för arbetet med kompetensförsörjning.";
const sourceUrl =
  "https://utvecklanorrbotten.se/nyheter/2026/norrbottens-rekryteringsbehov-8-500-personer-under-tva-ar/";
const results = [
  {
    value: "8 500",
    title: "personer behöver rekryteras",
    text: "Rekryteringsbehov i privat och offentlig sektor under kartläggningens tvåårshorisont.",
  },
  {
    value: "15 500",
    title: "anställda i offentlig sektor",
    text: "Omfattas av behov av kompetensutveckling enligt kartläggningen.",
  },
  {
    value: "6 200",
    title: "personer i näringslivet",
    text: "Omfattas av behov av kompetensutveckling enligt kartläggningen.",
  },
];

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Kompetensarena Norrbotten – kunskap för kompetensförsörjning" },
      { name: "description", content: description },
      {
        property: "og:title",
        content: "Kompetensarena Norrbotten – kunskap för kompetensförsörjning",
      },
      { property: "og:description", content: description },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: Startsida,
});

function Startsida() {
  return (
    <>
      <Section tone="light" className="relative overflow-hidden">
        <div
          aria-hidden
          className="pointer-events-none absolute -right-24 -top-24 size-80 rounded-full bg-brand-mid/30"
        />
        <div
          aria-hidden
          className="pointer-events-none absolute -bottom-32 right-40 size-56 rounded-full bg-accent-orange/30"
        />
        <div className="relative max-w-(--container-prose)">
          <p className="mb-4 text-sm uppercase tracking-[0.2em] text-ink-muted">{site.owner}</p>
          <h1 className="text-balance text-4xl leading-tight md:text-6xl">
            Kunskap för Norrbottens kompetensförsörjning
          </h1>
          <p className="mt-6 text-lg leading-relaxed text-ink">
            Vilken kompetens behöver Norrbotten, och hur kan behoven mötas? Kompetensarena
            Norrbotten tar avstamp i en kartläggning av arbetsgivarnas rekryterings- och
            kompetensutvecklingsbehov. Här sätts resultaten i ett bredare sammanhang tillsammans med
            statistik om arbetsmarknad, branscher och utbildning.
          </p>
          <p className="mt-4 text-lg leading-relaxed text-ink">
            Verktyget ger kommuner, arbetsgivare och utbildningsaktörer underlag för att planera,
            prioritera och arbeta tillsammans med kompetensförsörjningen.
          </p>
          <div className="mt-9 flex flex-wrap gap-3">
            <a
              href="#utforska"
              className="inline-flex items-center gap-2 rounded-lg bg-brand-dark px-5 py-3 text-white transition-colors hover:bg-brand-dark/90 active:bg-brand-dark/80"
            >
              Utforska verktyget
              <ArrowRight aria-hidden className="size-4" />
            </a>
            <Link
              to="/om"
              className="inline-flex items-center gap-2 rounded-lg border border-brand-dark px-5 py-3 text-brand-dark transition-colors hover:bg-surface"
            >
              Om Kompetensarena
            </Link>
          </div>
        </div>
      </Section>

      <Section>
        <div className="grid gap-8 md:grid-cols-2 md:gap-16">
          <div>
            <p className="mb-3 text-sm uppercase tracking-[0.15em] text-ink-muted">
              Kartläggning hösten 2025
            </p>
            <h2 className="text-3xl">Så kartlades behoven</h2>
            <p className="mt-5 leading-relaxed text-ink">
              Under hösten 2025 samlades svar in från flera hundra arbetsgivare i Norrbotten. Både
              näringslivet och offentlig sektor bidrog med uppgifter om behov av rekrytering och
              kompetensutveckling.
            </p>
            <p className="mt-4 leading-relaxed text-ink">
              Genom att samla in lokala data skapades en bild av behoven som kan användas i länets
              gemensamma arbete med kompetensförsörjning.
            </p>
          </div>
          <div className="border-t border-border pt-8 md:border-l md:border-t-0 md:pl-10 md:pt-0">
            <h3 className="text-2xl">Ett underlag för fortsatt arbete</h3>
            <p className="mt-5 leading-relaxed text-ink">
              Kartläggningen är en utgångspunkt för ett långsiktigt arbetssätt. Ambitionen är att
              återkommande insamling och aktiv användning av underlaget ska göra det lättare att
              upptäcka förändringar och planera insatser.
            </p>
            <p className="mt-4 leading-relaxed text-ink">
              Behoven handlar både om att rekrytera nya medarbetare och att utveckla kompetensen hos
              dem som redan arbetar i länet.
            </p>
          </div>
        </div>
      </Section>

      <Section tone="neutral">
        <h2 className="text-3xl">Detta visade kartläggningen</h2>
        <p className="mt-4 max-w-(--container-prose) leading-relaxed text-ink">
          Arbetsgivarna beskrev stora behov av både rekrytering och kompetensutveckling. Siffrorna
          nedan är ungefärliga och beskriver identifierade behov vid kartläggningen hösten 2025.
        </p>
        <ul className="mt-9 grid gap-5 md:grid-cols-3">
          {results.map((result) => (
            <li
              key={result.value}
              className="rounded-2xl border border-border bg-surface p-6 md:p-8"
            >
              <p className="text-sm text-ink-muted">Cirka</p>
              <p className="mt-1 font-heading text-5xl font-semibold tabular-nums text-brand-dark">
                {result.value}
              </p>
              <h3 className="mt-5 text-xl">{result.title}</h3>
              <p className="mt-3 leading-relaxed text-ink">{result.text}</p>
            </li>
          ))}
        </ul>
        <p className="mt-7 max-w-(--container-prose) leading-relaxed text-ink">
          Behov av stärkt kompetens framkom bland annat inom digitalisering, ledarskap, arbetsmiljö,
          verksamhetsutveckling och omställningsförmåga.
        </p>
        <p className="mt-5 text-sm leading-relaxed text-ink-muted">
          Rekryteringsbehovet avser kartläggningens tvåårshorisont, inte en löpande prognos från
          dagens datum. Källa: Region Norrbotten, publicerad 18 mars 2026.{" "}
          <a
            href={sourceUrl}
            className="text-brand-dark underline underline-offset-4 hover:no-underline"
          >
            Läs om kartläggningen och resultaten
          </a>
          .
        </p>
      </Section>

      <Section tone="dark" width="prose">
        <h2 className="text-3xl text-white">Från kunskap till handling</h2>
        <p className="mt-5 text-lg leading-relaxed text-white/90">
          Verktyget har använts som underlag för utbildningsplanering, prioritering av
          kompetensinsatser och dialog mellan arbetsgivare, utbildningsaktörer och andra
          samhällsaktörer. Det har också bidragit till analyser och till att synliggöra Norrbottens
          kompetensbehov i nationella sammanhang.
        </p>
        <p className="mt-5 text-lg leading-relaxed text-white/90">
          Genom att kombinera kartläggningens resultat med statistik om arbetsmarknad, branscher och
          utbildning ger verktyget stöd för det fortsatta arbetet med kompetensförsörjning på lokal
          och regional nivå.
        </p>
      </Section>

      <Section id="utforska" className="scroll-mt-20">
        <h2 className="text-3xl">Utforska verktyget</h2>
        <p className="mt-4 max-w-(--container-prose) leading-relaxed text-ink">
          Välj ett område för att undersöka behoven och deras sammanhang. Innehållet byggs ut
          stegvis och tillgängliga fördjupningar framgår på respektive områdessida.
        </p>
        <ul className="mt-9 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {areas.map((area) => (
            <li key={area.slug}>
              <AppLink
                href={areaPath(area.slug)}
                className="group flex h-full flex-col rounded-2xl border border-border bg-surface p-6 transition-colors hover:bg-brand-light"
              >
                <area.icon aria-hidden className="mb-4 size-7 text-brand-dark" />
                <h3 className="flex items-center justify-between gap-3 text-xl">
                  {area.title}
                  <ArrowRight aria-hidden className="size-4 shrink-0" />
                </h3>
                <p className="mt-3 leading-relaxed text-ink">{area.description}</p>
              </AppLink>
            </li>
          ))}
        </ul>
      </Section>
    </>
  );
}
