import { useEffect, useRef, useState } from "react";
import { ChevronDown } from "lucide-react";
import { mainNavigation } from "@/config/navigation";
import { AppLink } from "./AppLink";

/**
 * Desktopnavigation med undermenyer.
 *
 * Interaktion:
 * - hover öppnar, med kort fördröjning vid stängning så att musen hinner in
 * - klick/Enter/Space växlar (fungerar även med touch och tangentbord)
 * - piltangent ner öppnar, Escape stänger och återför fokus
 * - undermenyn stängs när fokus lämnar gruppen
 */
export function DesktopNav() {
  const [openIndex, setOpenIndex] = useState<number | null>(null);
  const closeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const navRef = useRef<HTMLElement>(null);

  useEffect(() => () => {
    if (closeTimer.current) clearTimeout(closeTimer.current);
  }, []);

  const cancelClose = () => {
    if (closeTimer.current) clearTimeout(closeTimer.current);
  };

  const scheduleClose = () => {
    cancelClose();
    closeTimer.current = setTimeout(() => setOpenIndex(null), 180);
  };

  return (
    <nav ref={navRef} aria-label="Huvudmeny" className="hidden lg:block">
      <ul className="flex items-stretch gap-1">
        {mainNavigation.map((group, index) => {
          const hasItems = Boolean(group.items?.length);
          const isOpen = openIndex === index;
          const panelId = `nav-panel-${index}`;

          return (
            <li
              key={group.label}
              className="relative"
              onMouseEnter={() => {
                if (!hasItems) return;
                cancelClose();
                setOpenIndex(index);
              }}
              onMouseLeave={() => hasItems && scheduleClose()}
              onBlur={(event) => {
                if (!event.currentTarget.contains(event.relatedTarget as Node)) {
                  setOpenIndex((current) => (current === index ? null : current));
                }
              }}
            >
              <div className="flex items-center">
                <AppLink
                  href={group.href}
                  className="rounded-md px-3 py-2 text-[0.95rem] font-normal text-ink transition-colors hover:bg-brand-light hover:text-brand-dark [&.active]:text-brand-dark [&.active]:underline [&.active]:underline-offset-8"
                  activeOptions={{ exact: group.href === "/" }}
                >
                  {group.label}
                </AppLink>
                {hasItems && (
                  <button
                    type="button"
                    aria-expanded={isOpen}
                    aria-controls={panelId}
                    aria-label={`${isOpen ? "Stäng" : "Öppna"} undermeny för ${group.label}`}
                    className="-ml-1 rounded-md p-1.5 text-ink transition-colors hover:bg-brand-light hover:text-brand-dark"
                    onClick={() => setOpenIndex(isOpen ? null : index)}
                    onKeyDown={(event) => {
                      if (event.key === "ArrowDown") {
                        event.preventDefault();
                        setOpenIndex(index);
                      }
                      if (event.key === "Escape") setOpenIndex(null);
                    }}
                  >
                    <ChevronDown
                      aria-hidden
                      className={`size-4 transition-transform ${isOpen ? "rotate-180" : ""}`}
                    />
                  </button>
                )}
              </div>

              {hasItems && isOpen && (
                <div
                  id={panelId}
                  className="absolute left-0 top-full z-50 w-80 pt-2"
                  onKeyDown={(event) => {
                    if (event.key === "Escape") setOpenIndex(null);
                  }}
                >
                  <ul className="rounded-xl border border-border bg-surface p-2 shadow-[0_12px_32px_-18px_rgba(51,51,51,0.45)]">
                    {group.items?.map((item) => (
                      <li key={`${item.label}-${item.href}`}>
                        <AppLink
                          href={item.href}
                          className="block rounded-lg px-3 py-2.5 transition-colors hover:bg-brand-light focus-visible:bg-brand-light"
                          onClick={() => setOpenIndex(null)}
                        >
                          <span className="block text-[0.95rem] text-brand-dark">
                            {item.label}
                          </span>
                          {item.description && (
                            <span className="mt-0.5 block text-sm text-ink-muted">
                              {item.description}
                            </span>
                          )}
                        </AppLink>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
