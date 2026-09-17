import { site } from "@/config/site";

export function Footer() {
  return (
    <footer className="mt-24 bg-brand-dark text-white">
      <div className="mx-auto w-full max-w-(--container-content) px-4 py-14 md:px-8">
        <p className="font-heading text-2xl text-white">{site.name}</p>
        <p className="mt-3 max-w-prose text-white/85">{site.tagline}</p>
        <p className="mt-8 text-sm text-white/75">
          En del av {site.owner}. Kontakt: {site.contactEmail}
        </p>
        <p className="mt-2 text-sm text-white/60">
          Webbplatsen är under uppbyggnad. Innehåll och statistik som visas nu är exempel.
        </p>
      </div>
    </footer>
  );
}
