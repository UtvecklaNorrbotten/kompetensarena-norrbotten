import { useEffect, useState } from "react";
import { ChevronDown, Menu, X } from "lucide-react";
import { mainNavigation } from "@/config/navigation";
import { AppLink } from "./AppLink";

/**
 * Mobilnavigation: hamburgerknapp som öppnar en panel över hela skärmen med
 * utfällbara undermenyer. Escape stänger, sidan låses från att scrolla.
 */
export function MobileNav() {
  const [open, setOpen] = useState(false);
  const [expanded, setExpanded] = useState<number | null>(null);

  useEffect(() => {
    if (!open) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    document.addEventListener("keydown", onKeyDown);
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKeyDown);
      document.body.style.overflow = "";
    };
  }, [open]);

  return (
    <div className="lg:hidden">
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-expanded={open}
        aria-controls="mobil-meny"
        className="inline-flex items-center gap-2 rounded-md px-3 py-2 text-ink transition-colors hover:bg-brand-light hover:text-brand-dark"
      >
        <Menu aria-hidden className="size-5" />
        Meny
      </button>

      {open && (
        <div
          id="mobil-meny"
          role="dialog"
          aria-modal="true"
          aria-label="Huvudmeny"
          className="fixed inset-0 z-50 flex flex-col bg-background"
        >
          <div className="flex items-center justify-between border-b border-border px-4 py-4">
            <span className="font-heading text-lg text-brand-dark">Meny</span>
            <button
              type="button"
              onClick={() => setOpen(false)}
              className="inline-flex items-center gap-2 rounded-md px-3 py-2 text-ink transition-colors hover:bg-brand-light hover:text-brand-dark"
              autoFocus
            >
              <X aria-hidden className="size-5" />
              Stäng
            </button>
          </div>

          <nav aria-label="Huvudmeny mobil" className="overflow-y-auto px-4 py-4">
            <ul className="space-y-1">
              {mainNavigation.map((group, index) => {
                const hasItems = Boolean(group.items?.length);
                const isExpanded = expanded === index;
                const panelId = `mobil-nav-panel-${index}`;

                return (
                  <li key={group.label} className="border-b border-border/70 pb-1">
                    <div className="flex items-center justify-between">
                      <AppLink
                        href={group.href}
                        onClick={() => setOpen(false)}
                        className="flex-1 rounded-md px-2 py-3 font-heading text-lg text-brand-dark"
                      >
                        {group.label}
                      </AppLink>
                      {hasItems && (
                        <button
                          type="button"
                          aria-expanded={isExpanded}
                          aria-controls={panelId}
                          aria-label={`${isExpanded ? "Dölj" : "Visa"} undermeny för ${group.label}`}
                          onClick={() => setExpanded(isExpanded ? null : index)}
                          className="rounded-md p-2.5 text-ink transition-colors hover:bg-brand-light"
                        >
                          <ChevronDown
                            aria-hidden
                            className={`size-5 transition-transform ${isExpanded ? "rotate-180" : ""}`}
                          />
                        </button>
                      )}
                    </div>

                    {hasItems && isExpanded && (
                      <ul id={panelId} className="mb-2 space-y-1 pl-2">
                        {group.items?.map((item) => (
                          <li key={`${item.label}-${item.href}`}>
                            <AppLink
                              href={item.href}
                              onClick={() => setOpen(false)}
                              className="block rounded-md px-2 py-2.5 text-ink transition-colors hover:bg-brand-light"
                            >
                              {item.label}
                            </AppLink>
                          </li>
                        ))}
                      </ul>
                    )}
                  </li>
                );
              })}
            </ul>
          </nav>
        </div>
      )}
    </div>
  );
}
