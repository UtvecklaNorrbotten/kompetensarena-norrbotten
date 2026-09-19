import { Link } from "@tanstack/react-router";
import { site } from "@/config/site";

const logo =
  "/__l5e/assets-v1/2013717c-364e-4945-a2dd-20e5fd7174f7/utveckla-norrbotten-vit-bakgrund.jpg";

/**
 * Huvudlogotypen använder Utveckla Norrbottens vita variant från Lovables
 * asset-lagring.
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
