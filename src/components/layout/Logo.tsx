import { Link } from "@tanstack/react-router";
import { site } from "@/config/site";
import logo from "@/assets/logo/kompetensarena-placeholder.svg";

/**
 * Logotypen behandlas som grafisk asset (SVG), inte som text.
 * Filen i src/assets/logo/ är en PLACEHOLDER och ska bytas mot den riktiga
 * logotypen från Utveckla Norrbotten.
 */
export function Logo() {
  return (
    <Link
      to="/"
      className="inline-flex items-center rounded-md py-1"
      aria-label={`${site.name} – till startsidan`}
    >
      <img src={logo} alt={site.name} className="h-11 w-auto" />
    </Link>
  );
}
