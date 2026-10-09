import { useEffect, useRef, useState } from "react";
import type { MouseEvent as ReactMouseEvent } from "react";
import { useRouterState } from "@tanstack/react-router";
import { BookOpen, Download, Home, PanelLeftClose, PanelLeftOpen, X } from "lucide-react";
import { areas, areaPath } from "@/config/areas";
import { Button } from "@/components/ui/button";
import { AppLink } from "./AppLink";

type Props = { mobileOpen: boolean; onMobileClose: () => void };

export function AreasSidebar({ mobileOpen, onMobileClose }: Props) {
  const pathname = useRouterState({ select: (state) => state.location.pathname });
  const [educationSection, setEducationSection] = useState("");
  const [pinned, setPinned] = useState(false);
  const [hovered, setHovered] = useState(false);
  const [focused, setFocused] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const panel = useRef<HTMLElement>(null);
  const restoreFocus = useRef<HTMLElement | null>(null);
  const desktopNav = useRef<HTMLElement>(null);
  const activeSlot = useRef<HTMLDivElement>(null);
  const [railLayout, setRailLayout] = useState({ height: 108, title: false, topic: false });
  const activeArea = areas.find(
    (area) => pathname.startsWith(areaPath(area.slug) + "/") || pathname === areaPath(area.slug),
  )?.slug;
  const selectedArea = areas.find((area) => area.slug === activeArea);
  const selectedTopic = selectedArea?.topics.find((topic) =>
    activeArea === "utbildning"
      ? educationSection === topic.slug
      : pathname === areaPath(selectedArea.slug, topic.slug),
  );
  const expanded = pinned || hovered || focused;

  useEffect(() => {
    const nav = desktopNav.current;
    const slot = activeSlot.current;
    if (!nav || !slot || !selectedArea) return;

    const measure = () => {
      // Measure the full navigation, including its footer, before allocating text space.
      const padding = getComputedStyle(nav);
      const contentHeight = Array.from(nav.children).reduce((total, child) => {
        const style = getComputedStyle(child);
        return total + child.getBoundingClientRect().height
          + parseFloat(style.marginTop) + parseFloat(style.marginBottom);
      }, 0);
      const available = Math.floor(nav.clientHeight
        - parseFloat(padding.paddingTop) - parseFloat(padding.paddingBottom)
        - contentHeight + slot.getBoundingClientRect().height);
      const titleHeight = Array.from(selectedArea.title).length * 14 + 12;
      const textMeasure = document.createElement("canvas").getContext("2d");
      if (textMeasure) textMeasure.font = `11px ${padding.fontFamily}`;
      const topicHeight = selectedTopic
        ? Math.ceil(textMeasure?.measureText(selectedTopic.title).width
          ?? Array.from(selectedTopic.title).length * 7) + 12
        : 0;
      const title = available >= titleHeight;
      // The topic uses the same vertical space as the area, never extra row height.
      const height = Math.max(108, title ? titleHeight : 0);
      const topic = title && !!selectedTopic && topicHeight <= height;
      setRailLayout((previous) =>
        previous.height === height && previous.title === title && previous.topic === topic
          ? previous
          : { height, title, topic },
      );
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(nav);
    return () => observer.disconnect();
  }, [selectedArea, selectedTopic]);
  const rowClass =
    "relative flex h-10 items-center gap-3 whitespace-nowrap rounded-md p-2 hover:bg-brand-light";
  const activeRowClass =
    "bg-brand-light font-semibold text-brand-dark before:absolute before:inset-y-2 before:left-0 before:w-[3px] before:rounded-full before:bg-brand-dark before:content-['']";
  const navRowClass = (active: boolean) => `${rowClass} ${active ? activeRowClass : ""}`;

  useEffect(() => {
    if (!mobileOpen) return;
    restoreFocus.current = document.activeElement as HTMLElement;
    const oldOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    panel.current?.focus();
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onMobileClose();
      if (event.key !== "Tab" || !panel.current) return;
      const items = Array.from(
        panel.current.querySelectorAll<HTMLElement>("a[href],button:not([disabled])"),
      );
      const first = items[0],
        last = items[items.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last?.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first?.focus();
      }
    };
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.body.style.overflow = oldOverflow;
      document.removeEventListener("keydown", onKeyDown);
      restoreFocus.current?.focus();
    };
  }, [mobileOpen, onMobileClose]);

  useEffect(() => {
    const handler = (event: Event) => setEducationSection((event as CustomEvent<string>).detail);
    window.addEventListener("education-section", handler);
    return () => window.removeEventListener("education-section", handler);
  }, []);

  useEffect(() => {
    onMobileClose();
  }, [pathname, onMobileClose]); // Navigation closes the mobile panel.

  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current);
    },
    [],
  );

  // Ett musklick ska lämna fokus på länken (menyn styrs annars av hovring).
  const blurOnClick = (event: ReactMouseEvent<HTMLAnchorElement>) => {
    if (event.detail > 0) event.currentTarget.blur();
  };

  const nav = (mobile: boolean) => (
    <nav
      ref={mobile ? undefined : desktopNav}
      aria-label="Områden"
      className="flex h-full flex-col overflow-y-auto py-3"
    >
      <div className="mb-2 flex h-9 shrink-0 items-center justify-between px-2">
        <span
          aria-hidden={!expanded && !mobile}
          className={`px-2 text-sm font-semibold text-brand-dark ${expanded || mobile ? "" : "invisible"}`}
        >
          Områden
        </span>
        {mobile ? (
          <Button
            variant="ghost"
            size="icon"
            type="button"
            onClick={onMobileClose}
            aria-label="Stäng menyn"
          >
            <X className="size-5" />
          </Button>
        ) : (
          <Button
            variant="ghost"
            size="icon"
            type="button"
            onClick={() => setPinned(!pinned)}
            aria-label={pinned ? "Lås upp menyn" : "Lås menyn utfälld"}
            aria-pressed={pinned}
            title={pinned ? "Lås upp menyn" : "Lås menyn utfälld"}
          >
            {pinned ? <PanelLeftClose className="size-5" /> : <PanelLeftOpen className="size-5" />}
          </Button>
        )}
      </div>
      <ul className="shrink-0 space-y-1 px-2">
        <li>
          <AppLink
            href="/"
            onClick={blurOnClick}
            aria-label="Startsida"
            title="Startsida"
            className={navRowClass(pathname === "/")}
          >
            <Home className="size-5 shrink-0" />
            <span className={expanded || mobile ? "" : "sr-only"}>Startsida</span>
          </AppLink>
        </li>
        {areas.map((area) => {
          const Icon = area.icon;
          const TopicLink = area.slug === "utbildning" ? "a" : AppLink;
          const open = activeArea === area.slug;
          // Behåll det aktiva områdets undermeny i layouten även när sidomenyn är hopfälld.
          // Annars flyttar ikonerna nedåt när menyn expanderas vid hovring.
          const showSub = open;
          return (
            <li key={area.slug}>
              <AppLink
                href={areaPath(area.slug)}
                onClick={blurOnClick}
                activeOptions={{ exact: true }}
                title={area.title}
                className={navRowClass(open)}
              >
                <Icon className="size-5 shrink-0" />
                <span className={expanded || mobile ? "" : "sr-only"}>{area.title}</span>
              </AppLink>
              {showSub && (
                <div
                  ref={mobile ? undefined : activeSlot}
                  className="relative"
                  style={mobile ? undefined : { minHeight: railLayout.height }}
                >
                  {!mobile && !expanded && railLayout.title && (
                    <div className="absolute left-2 top-0 flex w-[39px] items-start gap-1 pt-1.5">
                      <AppLink
                        href={areaPath(area.slug)}
                        onClick={blurOnClick}
                        aria-label={area.title}
                        title={area.title}
                        className="flex w-5 shrink-0 flex-col items-center text-[13px] font-semibold leading-[14px] text-brand-dark"
                      >
                        <span aria-hidden="true" className="flex flex-col items-center">
                          {Array.from(area.title).map((letter, index) => (
                            <span key={index} className="h-[14px]">{letter === " " ? "\u00a0" : letter}</span>
                          ))}
                        </span>
                      </AppLink>
                      {railLayout.topic && selectedTopic && (
                        <TopicLink
                          href={area.slug === "utbildning"
                            ? "#" + selectedTopic.slug
                            : areaPath(area.slug, selectedTopic.slug)}
                          onClick={blurOnClick}
                          aria-label={selectedTopic.title}
                          title={selectedTopic.title}
                          className="flex w-[15px] shrink-0 flex-col items-center border-l border-border pl-1 text-[11px] leading-[13px] text-ink-muted"
                        >
                          <span
                            aria-hidden="true"
                            className="whitespace-nowrap"
                            style={{ writingMode: "vertical-rl" }}
                          >
                            {selectedTopic.title}
                          </span>
                        </TopicLink>
                      )}
                    </div>
                  )}
                  <ul
                    aria-hidden={!expanded && !mobile}
                    className={`ml-8 border-l border-border pl-2 text-sm ${expanded || mobile ? "" : "invisible"}`}
                  >
                    <li>
                      {area.slug === "utbildning" ? (
                        <a
                          href="#utbildning-oversikt"
                          tabIndex={expanded || mobile ? undefined : -1}
                          onClick={(event) => {
                            blurOnClick(event);
                            onMobileClose();
                          }}
                          aria-current={!educationSection ? "location" : undefined}
                          className={`flex h-9 items-center whitespace-nowrap rounded p-2 hover:bg-brand-light ${!educationSection ? "bg-brand-light text-brand-dark" : ""}`}
                        >
                          Översikt
                        </a>
                      ) : (
                        <AppLink
                          tabIndex={expanded || mobile ? undefined : -1}
                          onClick={blurOnClick}
                          href={areaPath(area.slug)}
                          activeOptions={{ exact: true }}
                          className="flex h-9 items-center whitespace-nowrap rounded p-2 hover:bg-brand-light aria-[current=page]:bg-brand-light"
                        >
                          Översikt
                        </AppLink>
                      )}
                    </li>
                    {area.topics.map((topic) => (
                      <li key={topic.slug}>
                        {area.slug === "utbildning" ? (
                          <a
                            href={`#${topic.slug}`}
                            tabIndex={expanded || mobile ? undefined : -1}
                            onClick={(event) => {
                              blurOnClick(event);
                              onMobileClose();
                            }}
                            aria-current={educationSection === topic.slug ? "location" : undefined}
                            className={`flex h-9 items-center whitespace-nowrap rounded p-2 hover:bg-brand-light ${educationSection === topic.slug ? "bg-brand-light font-semibold text-brand-dark" : ""}`}
                          >
                            {topic.title}
                          </a>
                        ) : (
                          <AppLink
                            tabIndex={expanded || mobile ? undefined : -1}
                            onClick={blurOnClick}
                            href={areaPath(area.slug, topic.slug)}
                            activeOptions={{ exact: true }}
                            className="flex h-9 items-center whitespace-nowrap rounded p-2 hover:bg-brand-light aria-[current=page]:bg-brand-light"
                          >
                            {topic.title}
                          </AppLink>
                        )}
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </li>
          );
        })}
      </ul>
      <div className="mt-5 shrink-0 border-t border-border px-2 pt-3">
        <p
          aria-hidden={!expanded && !mobile}
          className={`h-6 whitespace-nowrap px-2 pb-2 text-xs font-semibold uppercase text-ink-muted ${expanded || mobile ? "" : "invisible"}`}
        >
          Data och metod
        </p>
        <AppLink
          href="/om"
          onClick={blurOnClick}
          title="Om"
          className={navRowClass(pathname === "/om")}
        >
          <BookOpen className="size-5 shrink-0" />
          <span className={expanded || mobile ? "" : "sr-only"}>Om</span>
        </AppLink>
        <AppLink
          href="/ladda-ned-data"
          onClick={blurOnClick}
          title="Ladda ned data"
          className={navRowClass(pathname === "/ladda-ned-data")}
        >
          <Download className="size-5 shrink-0" />
          <span className={expanded || mobile ? "" : "sr-only"}>Ladda ned data</span>
        </AppLink>
      </div>
    </nav>
  );

  return (
    <>
      <div aria-hidden className="hidden w-14 shrink-0 md:block" />
      <aside
        aria-label="Områdesmeny"
        onMouseEnter={() => {
          if (timer.current) clearTimeout(timer.current);
          timer.current = setTimeout(() => setHovered(true), 120);
        }}
        onMouseLeave={() => {
          if (timer.current) clearTimeout(timer.current);
          timer.current = setTimeout(() => setHovered(false), 180);
        }}
        onFocus={() => setFocused(true)}
        onBlur={(event) => {
          if (!event.currentTarget.contains(event.relatedTarget)) setFocused(false);
        }}
        className={`fixed bottom-0 left-0 top-[72px] z-30 hidden border-r border-border bg-surface shadow-md transition-[width] md:block ${expanded ? "w-[220px]" : "w-14"}`}
      >
        {nav(false)}
      </aside>
      {mobileOpen && (
        <div className="fixed inset-0 z-50 md:hidden">
          <button
            type="button"
            aria-label="Stäng menyn"
            onClick={onMobileClose}
            className="absolute inset-0 bg-black/40"
          />
          <aside
            ref={panel}
            tabIndex={-1}
            role="dialog"
            aria-modal="true"
            aria-label="Områdesmeny"
            className="absolute inset-y-0 left-0 w-[min(85vw,280px)] bg-surface shadow-xl"
          >
            {nav(true)}
          </aside>
        </div>
      )}
    </>
  );
}
