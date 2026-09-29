import { useEffect, useRef, useState } from "react";
import { useServerFn } from "@tanstack/react-start";
import { Search, X } from "lucide-react";
import { searchSite, type SearchHit } from "@/lib/search.functions";
import { AppLink } from "./AppLink";

export function SiteSearch() {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [hits, setHits] = useState<SearchHit[]>([]);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState(false);
  const input = useRef<HTMLInputElement>(null);
  const previousFocus = useRef<HTMLElement | null>(null);
  const search = useServerFn(searchSite);

  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
        event.preventDefault(); setOpen(true);
      }
      if (event.key === "Escape") setOpen(false);
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, []);

  useEffect(() => {
    if (!open) return;
    previousFocus.current = document.activeElement as HTMLElement;
    const oldOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    input.current?.focus();
    return () => { document.body.style.overflow = oldOverflow; previousFocus.current?.focus(); };
  }, [open]);

  useEffect(() => {
    if (!open || query.trim().length < 2) { setHits([]); setPending(false); setError(false); return; }
    let cancelled = false;
    const timeout = setTimeout(async () => {
      setPending(true); setError(false);
      try {
        const result = await search({ data: { query: query.trim() } });
        if (!cancelled) setHits(result);
      } catch { if (!cancelled) { setHits([]); setError(true); } }
      finally { if (!cancelled) setPending(false); }
    }, 250);
    return () => { cancelled = true; clearTimeout(timeout); };
  }, [open, query, search]);

  return (
    <>
      <button type="button" onClick={() => setOpen(true)} className="inline-flex items-center gap-2 rounded-md border border-border px-3 py-2 text-sm hover:bg-brand-light" aria-label="Sök på webbplatsen">
        <Search aria-hidden className="size-4" /><span className="hidden sm:inline">Sök</span><kbd className="hidden rounded bg-neutral-surface px-1 text-xs lg:inline">Ctrl K</kbd>
      </button>
      {open && (
        <div className="fixed inset-0 z-50 flex items-start justify-center px-4 pt-[10vh]">
          <button type="button" aria-label="Stäng sökningen" onClick={() => setOpen(false)} className="absolute inset-0 bg-black/50" />
          <div role="dialog" aria-modal="true" aria-label="Sök på webbplatsen" onKeyDown={(event) => {
            if (event.key !== "Tab") return;
            const focusables = Array.from(event.currentTarget.querySelectorAll<HTMLElement>('input,button,a[href]'));
            const first = focusables[0], last = focusables[focusables.length - 1];
            if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
            else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
          }} className="relative w-full max-w-xl rounded-xl bg-surface p-5 shadow-xl">
            <div className="flex items-center gap-2">
              <Search aria-hidden className="size-5" />
              <label htmlFor="site-search" className="sr-only">Sökord</label>
              <input ref={input} id="site-search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Sök sidor, indikatorer och områden" className="min-w-0 flex-1 rounded border border-input p-2" />
              <button type="button" onClick={() => setOpen(false)} aria-label="Stäng sökningen" className="rounded p-2 hover:bg-brand-light"><X className="size-5" /></button>
            </div>
            <div aria-live="polite" className="mt-4 max-h-[60vh] overflow-y-auto">
              {pending && <p className="text-sm text-ink-muted">Söker…</p>}
              {error && <p role="alert" className="text-sm text-destructive">Sökningen är tillfälligt otillgänglig.</p>}
              {!pending && !error && query.trim().length >= 2 && hits.length === 0 && <p className="text-sm text-ink-muted">Inga träffar.</p>}
              <ul className="space-y-1">
                {hits.map((hit) => <li key={hit.url + hit.title}>
                  <AppLink href={hit.url} onClick={() => setOpen(false)} className="block rounded-md p-3 hover:bg-brand-light">
                    <span className="text-xs uppercase text-ink-muted">{hit.kind}</span>
                    <span className="block font-semibold text-brand-dark">{hit.title}</span>
                    {hit.description && <span className="block text-sm text-ink-muted">{hit.description}</span>}
                  </AppLink>
                </li>)}
              </ul>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
