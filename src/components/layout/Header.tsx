import { DesktopNav } from "./DesktopNav";
import { MobileNav } from "./MobileNav";
import { Logo } from "./Logo";
import { AccountLink } from "./AccountLink";

// Obs: ingen backdrop-blur på headern – det skapar en containing block och
// bryter mobilmenyns fixed-positionering.
export function Header() {
  return (
    <header className="sticky top-0 z-40 border-b border-border bg-surface">
      <div className="mx-auto flex w-full max-w-(--container-content) items-center justify-between gap-6 px-4 py-3 md:px-8">
        <Logo />
        <DesktopNav />
        <AccountLink />
        <MobileNav />
      </div>
    </header>
  );
}
