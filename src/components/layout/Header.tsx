import { DesktopNav } from "./DesktopNav";
import { MobileNav } from "./MobileNav";
import { Logo } from "./Logo";

export function Header() {
  return (
    {/* Obs: ingen backdrop-blur här – det skapar containing block och bryter
        mobilmenyns fixed-positionering. */}
    <header className="sticky top-0 z-40 border-b border-border bg-surface">
      <div className="mx-auto flex w-full max-w-(--container-content) items-center justify-between gap-6 px-4 py-3 md:px-8">
        <Logo />
        <DesktopNav />
        <MobileNav />
      </div>
    </header>
  );
}
