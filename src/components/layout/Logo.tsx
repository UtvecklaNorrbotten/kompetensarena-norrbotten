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
      className="inline-flex h-full shrink-0 items-center rounded-md"
      aria-label={`${site.name} – till startsidan`}
    >
      <img src={logo} alt={site.name} className="block h-10 w-auto max-w-[40vw] object-contain md:h-[70px] md:w-[240px] md:max-w-none md:object-cover md:object-left" />
    </Link>
  );
}
