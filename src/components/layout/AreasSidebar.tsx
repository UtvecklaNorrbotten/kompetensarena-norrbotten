import { useEffect, useRef, useState } from "react";
import { useRouterState } from "@tanstack/react-router";
import { BookOpen, Download, Home, PanelLeftClose, PanelLeftOpen, X } from "lucide-react";
import { areas, areaPath } from "@/config/areas";
import { Button } from "@/components/ui/button";
import { AppLink } from "./AppLink";

type Props = { mobileOpen: boolean; onMobileClose: () => void };

export function AreasSidebar({ mobileOpen, onMobileClose }: Props) {
  const pathname = useRouterState({ select: (state) => state.location.pathname });
  const [pinned, setPinned] = useState(false);
  const [hovered, setHovered] = useState(false);
  const [focused, setFocused] = useState(false);
  const [hoveredArea, setHoveredArea] = useState<string | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const areaTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const panel = useRef<HTMLElement>(null);
  const restoreFocus = useRef<HTMLElement | null>(null);
  const activeArea = areas.find((area) => pathname.startsWith(areaPath(area.slug) + "/") || pathname === areaPath(area.slug))?.slug;
  const expanded = pinned || hovered || focused;
  const rowClass = "flex h-10 items-center gap-3 whitespace-nowrap rounded-md p-2 hover:bg-brand-light";

  const openArea = (slug: string) => {
    if (areaTimer.current) clearTimeout(areaTimer.current);
    setHoveredArea(slug);
  };
  const closeArea = () => {
    if (areaTimer.current) clearTimeout(areaTimer.current);
    areaTimer.current = setTimeout(() => setHoveredArea(null), 180);
  };

  useEffect(() => {
    if (!mobileOpen) return;
    restoreFocus.current = document.activeElement as HTMLElement;
    const oldOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    panel.current?.focus();
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onMobileClose();
      if (event.key !== "Tab" || !panel.current) return;
      const items = Array.from(panel.current.querySelectorAll<HTMLElement>('a[href],button:not([disabled])'));
      const first = items[0], last = items[items.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
    };
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.body.style.overflow = oldOverflow;
      document.removeEventListener("keydown", onKeyDown);
      restoreFocus.current?.focus();
    };
  }, [mobileOpen, onMobileClose]);

  useEffect(() => { onMobileClose(); }, [pathname, onMobileClose]); // Navigation closes the mobile panel.

  useEffect(() => () => { if (timer.current) clearTimeout(timer.current); if (areaTimer.current) clearTimeout(areaTimer.current); }, []);

  const nav = (mobile: boolean) => (
    <nav aria-label="Områden" className="flex h-full flex-col overflow-y-auto py-3">
      <div className="mb-2 flex h-9 items-center justify-between px-2">
        <span aria-hidden={!expanded && !mobile} className={`px-2 text-sm font-semibold text-brand-dark ${expanded || mobile ? "" : "invisible"}`}>Områden</span>
        {mobile ? (
          <Button variant="ghost" size="icon" type="button" onClick={onMobileClose} aria-label="Stäng menyn"><X className="size-5" /></Button>
        ) : (
          <Button variant="ghost" size="icon" type="button" onClick={() => setPinned(!pinned)} aria-label={pinned ? "Lås upp menyn" : "Lås menyn utfälld"} aria-pressed={pinned} title={pinned ? "Lås upp menyn" : "Lås menyn utfälld"}>
            {pinned ? <PanelLeftClose className="size-5" /> : <PanelLeftOpen className="size-5" />}
          </Button>
        )}
      </div>
      <ul className="space-y-1 px-2">
        <li><AppLink href="/" aria-label="Startsida" title="Startsida" className={rowClass}><Home className="size-5 shrink-0" /><span className={expanded || mobile ? "" : "sr-only"}>Startsida</span></AppLink></li>
        {areas.map((area) => {
          const Icon = area.icon;
          const open = activeArea === area.slug;
          const showSub = mobile ? open : open || hoveredArea === area.slug;
          return (
            <li key={area.slug} onMouseEnter={() => openArea(area.slug)} onMouseLeave={closeArea} onFocus={() => openArea(area.slug)} onBlur={(event) => { if (!event.currentTarget.contains(event.relatedTarget)) closeArea(); }}>
              <AppLink href={areaPath(area.slug)} activeOptions={{ exact: true }} title={area.title} className={rowClass}>
                <Icon className="size-5 shrink-0" /><span className={expanded || mobile ? "" : "sr-only"}>{area.title}</span>
              </AppLink>
              {showSub && (
                <ul aria-hidden={!expanded && !mobile} className={`ml-8 border-l border-border pl-2 text-sm ${expanded || mobile ? "" : "invisible"}`}>
                  <li><AppLink tabIndex={expanded || mobile ? undefined : -1} href={areaPath(area.slug)} activeOptions={{ exact: true }} className="flex h-9 items-center whitespace-nowrap rounded p-2 hover:bg-brand-light aria-[current=page]:bg-brand-light">Översikt</AppLink></li>
                  {area.topics.map((topic) => (
                    <li key={topic.slug}><AppLink tabIndex={expanded || mobile ? undefined : -1} href={areaPath(area.slug, topic.slug)} activeOptions={{ exact: true }} className="flex h-9 items-center whitespace-nowrap rounded p-2 hover:bg-brand-light aria-[current=page]:bg-brand-light">{topic.title}</AppLink></li>
                  ))}
                </ul>
              )}
            </li>
          );
        })}
      </ul>
      <div className="mt-5 border-t border-border px-2 pt-3">
        <p aria-hidden={!expanded && !mobile} className={`h-6 whitespace-nowrap px-2 pb-2 text-xs font-semibold uppercase text-ink-muted ${expanded || mobile ? "" : "invisible"}`}>Data och metod</p>
        <AppLink href="/om" title="Om" className={rowClass}><BookOpen className="size-5 shrink-0" /><span className={expanded || mobile ? "" : "sr-only"}>Om</span></AppLink>
        <AppLink href="/ladda-ned-data" title="Ladda ned data" className={rowClass}><Download className="size-5 shrink-0" /><span className={expanded || mobile ? "" : "sr-only"}>Ladda ned data</span></AppLink>
      </div>
    </nav>
  );

  return (
    <>
      <div aria-hidden className="hidden w-14 shrink-0 md:block" />
      <aside aria-label="Områdesmeny" onMouseEnter={() => { if (timer.current) clearTimeout(timer.current); timer.current = setTimeout(() => setHovered(true), 120); }} onMouseLeave={() => { if (timer.current) clearTimeout(timer.current); timer.current = setTimeout(() => setHovered(false), 180); }} onFocus={() => setFocused(true)} onBlur={(event) => { if (!event.currentTarget.contains(event.relatedTarget)) setFocused(false); }} className={`fixed bottom-0 left-0 top-[72px] z-30 hidden border-r border-border bg-surface shadow-md transition-[width] md:block ${expanded ? "w-[220px]" : "w-14"}`}>
        {nav(false)}
      </aside>
      {mobileOpen && (
        <div className="fixed inset-0 z-50 md:hidden">
          <button type="button" aria-label="Stäng menyn" onClick={onMobileClose} className="absolute inset-0 bg-black/40" />
          <aside ref={panel} tabIndex={-1} role="dialog" aria-modal="true" aria-label="Områdesmeny" className="absolute inset-y-0 left-0 w-[min(85vw,280px)] bg-surface shadow-xl">
            {nav(true)}
          </aside>
        </div>
      )}
    </>
  );
}
