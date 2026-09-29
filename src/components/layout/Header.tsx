import { Menu } from "lucide-react";
import { Logo } from "./Logo";
import { AccountLink } from "./AccountLink";
import { SiteSearch } from "./SiteSearch";

export function Header({ onOpenMenu }: { onOpenMenu: () => void }) {
  return (
    <header className="sticky top-0 z-40 h-[72px] border-b border-border bg-surface">
      <div className="mx-auto flex h-full w-full max-w-(--container-content) items-center justify-between gap-3 px-4 md:px-8">
        <button type="button" onClick={onOpenMenu} aria-label="Öppna områdesmenyn" className="rounded p-2 hover:bg-brand-light md:hidden"><Menu className="size-5" /></button>
        <Logo />
        <div className="ml-auto flex items-center gap-2"><SiteSearch /><AccountLink /></div>
      </div>
    </header>
  );
}
