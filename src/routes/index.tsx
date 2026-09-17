import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowRight } from "lucide-react";
import { Section } from "@/components/layout/Section";
import { site } from "@/config/site";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Kompetensarena Norrbotten – kunskap om kompetensförsörjning" },
      { name: "description", content: site.description },
      {
        property: "og:title",
        content: "Kompetensarena Norrbotten – kunskap om kompetensförsörjning",
      },
      { property: "og:description", content: site.description },
    ],
  }),
  component: Startsida,
});

function Startsida() {
  return (
    <>
      {/* Hero */}
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
          <p className="mb-4 text-sm uppercase tracking-[0.2em] text-ink-muted">
            {site.owner}
          </p>
          <h1 className="text-balance text-4xl leading-tight md:text-6xl">
            Kunskap om kompetensförsörjning i Norrbotten
          </h1>
          <p className="mt-6 text-lg leading-relaxed text-ink">
            Norrbottens utmaningar inom kompetensförsörjning är stora – vi bryter ny
            mark i bred samverkan. Här samlas statistik, analyser och kunskap som stöd
            för regionens gemensamma arbete.
          </p>
          <div className="mt-9 flex flex-wrap gap-3">
            <Link
              to="/statistik"
              className="inline-flex items-center gap-2 rounded-lg bg-brand-dark px-5 py-3 text-white transition-colors hover:bg-brand-dark/90 active:bg-brand-dark/80"
            >
              Se exempel på statistik
              <ArrowRight aria-hidden className="size-4" />
            </Link>
            <Link
              to="/om"
              className="inline-flex items-center gap-2 rounded-lg border border-brand-dark px-5 py-3 text-brand-dark transition-colors hover:bg-surface"
            >
              Om Kompetensarena
            </Link>
          </div>
        </div>
      </Section>

      {/* Tre områden – visar formspråket, inte färdigt innehåll */}
      <Section>
        <h2 className="text-3xl">Plattformen byggs stegvis</h2>
        <p className="mt-4 max-w-(--container-prose) text-ink">
          Den här versionen visar webbplatsens grundläggande struktur, form och tekniska
          uppbyggnad. Innehållet nedan är exempel och kommer att ersättas.
        </p>
        <ul className="mt-10 grid gap-6 md:grid-cols-3">
          {[
            {
              title: "Statistik och indikatorer",
              text: "Nyckeltal och tidsserier med tydlig källa och uppdateringsdatum.",
            },
            {
              title: "Analys och sammanhang",
              text: "Förklarande texter som sätter siffrorna i ett regionalt sammanhang.",
            },
            {
              title: "Underlag för samverkan",
              text: "Gemensamt kunskapsunderlag för aktörer i Norrbotten.",
            },
          ].map((item) => (
            <li
              key={item.title}
              className="rounded-2xl border border-border bg-surface p-7"
            >
              <span
                aria-hidden
                className="mb-5 block size-10 rounded-full bg-brand-mid"
              />
              <h3 className="text-xl">{item.title}</h3>
              <p className="mt-3 text-ink">{item.text}</p>
            </li>
          ))}
        </ul>
      </Section>

      <Section tone="dark" width="prose">
        <h2 className="text-3xl text-white">Ett gemensamt kunskapsunderlag</h2>
        <p className="mt-5 text-lg leading-relaxed text-white/90">
          Kompetensarena Norrbotten samlar aktörer inom näringsliv, utbildning och
          offentlig sektor. Målet är att beslut om kompetensförsörjning ska vila på
          samma kunskap och samma data.
        </p>
      </Section>
    </>
  );
}
