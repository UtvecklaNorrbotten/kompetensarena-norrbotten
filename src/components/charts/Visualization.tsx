import { useEffect, useRef, useState, type ReactNode } from "react";
import {
  Clipboard,
  Download,
  FileSpreadsheet,
  Maximize,
  MoreHorizontal,
  X,
} from "@/components/icons";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { VisualizationPortal } from "./visualization-context";
import { cn } from "@/lib/utils";
import {
  citation,
  filterText,
  sourceName,
  type VisualizationExport,
} from "@/lib/visualization-export";

export function Visualization({
  data,
  children,
  className,
  id,
  exportReady = true,
  fullscreenFilters,
  fullscreenHeading = false,
}: {
  data: VisualizationExport | undefined;
  children: ReactNode;
  className?: string;
  id?: string;
  exportReady?: boolean;
  fullscreenFilters?: ReactNode;
  fullscreenHeading?: boolean;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const close = useRef<HTMLButtonElement>(null);
  const [fullscreen, setFullscreen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    if (!message || failed) return;
    const timer = window.setTimeout(() => setMessage(""), 4000);
    return () => window.clearTimeout(timer);
  }, [message, failed]);

  async function run(action: () => Promise<void>, confirmation: string, error: string) {
    setBusy(true);
    setMessage("");
    setFailed(false);
    try {
      await action();
      setMessage(confirmation);
    } catch {
      setMessage(error);
      setFailed(true);
    } finally {
      setBusy(false);
    }
  }

  return (
    <dialog
      ref={dialog}
      className="visualization-dialog"
      data-export-selection={
        data ? JSON.stringify([data.filename, data.period, data.filters]) : undefined
      }
      aria-label={data?.title}
      onClose={() => {
        setFullscreen(false);
        requestAnimationFrame(() => trigger.current?.focus({ preventScroll: true }));
      }}
    >
      <VisualizationPortal.Provider value={fullscreen ? dialog.current : null}>
        <div id={id} className={cn("visualization-content relative min-w-0", className)}>
          {data && (
            <div
              className={
                fullscreen ? "sticky top-4 z-20 ml-auto h-0 w-fit" : "absolute top-4 right-4 z-10"
              }
            >
              {fullscreen ? (
                <button
                  ref={close}
                  type="button"
                  onClick={() => dialog.current?.close()}
                  className="inline-flex min-h-11 min-w-11 items-center justify-center rounded-md border border-border bg-surface text-ink hover:bg-brand-light"
                  aria-label="Stäng helskärm"
                >
                  <X className="size-5" aria-hidden />
                </button>
              ) : (
                <DropdownMenu modal={false}>
                  <DropdownMenuTrigger asChild>
                    <button
                      ref={trigger}
                      type="button"
                      className="inline-flex min-h-11 min-w-11 items-center justify-center rounded-md text-ink-muted hover:bg-brand-light hover:text-ink"
                      aria-label={`Diagrammeny för ${data.title}`}
                    >
                      <MoreHorizontal className="size-5" aria-hidden />
                    </button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent
                    align="end"
                    className="data-[state=open]:animate-none data-[state=closed]:animate-none"
                  >
                    <DropdownMenuItem
                      disabled={!exportReady || busy}
                      onSelect={() => {
                        const parts = [
                          ...(dialog.current?.querySelectorAll<HTMLElement>(
                            "[data-visualization-export]",
                          ) ?? []),
                        ];
                        const selection = dialog.current?.dataset.exportSelection;
                        void run(
                          async () => {
                            const { saveVisualizationImage } =
                              await import("@/lib/visualization-image");
                            if (selection !== dialog.current?.dataset.exportSelection)
                              throw new Error("Urvalet ändrades.");
                            await saveVisualizationImage(parts, data);
                          },
                          "Diagrammet har laddats ned.",
                          "Diagrammet kunde inte laddas ned. Försök igen.",
                        );
                      }}
                    >
                      <Download aria-hidden /> Ladda ned diagram (PNG)
                    </DropdownMenuItem>
                    <DropdownMenuItem
                      disabled={!exportReady || !data.rows.length || busy}
                      onSelect={() =>
                        void run(
                          async () => {
                            const { saveVisualizationWorkbook } =
                              await import("@/lib/visualization-workbook");
                            await saveVisualizationWorkbook(data);
                          },
                          "Statistiken har laddats ned.",
                          "Statistiken kunde inte laddas ned. Försök igen.",
                        )
                      }
                    >
                      <FileSpreadsheet aria-hidden /> Ladda ned statistik (Excel)
                    </DropdownMenuItem>
                    <DropdownMenuItem
                      disabled={!exportReady || busy}
                      onSelect={() =>
                        void run(
                          () => navigator.clipboard.writeText(citation(data, window.location.href)),
                          "Källhänvisningen har kopierats.",
                          "Källhänvisningen kunde inte kopieras.",
                        )
                      }
                    >
                      <Clipboard aria-hidden /> Kopiera källhänvisning
                    </DropdownMenuItem>
                    <DropdownMenuItem
                      onSelect={() => {
                        requestAnimationFrame(() => {
                          if (!dialog.current || dialog.current.open) return;
                          dialog.current.showModal();
                          setFullscreen(true);
                          requestAnimationFrame(() => close.current?.focus());
                        });
                      }}
                    >
                      <Maximize aria-hidden /> Visa i helskärm
                    </DropdownMenuItem>
                  </DropdownMenuContent>
                </DropdownMenu>
              )}
            </div>
          )}
          {fullscreen && data && (
            <div className="mb-4 pr-12 text-sm text-ink-muted">
              {fullscreenHeading && <h2 className="mb-2 text-2xl text-ink">{data.title}</h2>}
              {fullscreenHeading && data.subtitle && <p>{data.subtitle}</p>}
              {data.filters && <p className="mt-1">{filterText(data.filters)}</p>}
              {data.period && <p className="mt-1">Referensperiod: {data.period}</p>}
            </div>
          )}
          {fullscreen && fullscreenFilters && (
            <details className="mb-5 pr-12">
              <summary className="w-fit cursor-pointer rounded-md border border-border px-3 py-2 text-sm text-brand-dark">
                Ändra urval
              </summary>
              {fullscreenFilters}
            </details>
          )}
          {children}
          {fullscreen && fullscreenHeading && data && (
            <p className="mt-4 text-sm text-ink-muted">
              Källa:{" "}
              {data.source.url ? (
                <a className="underline" href={data.source.url} target="_blank" rel="noreferrer">
                  {sourceName(data.source)}
                </a>
              ) : (
                sourceName(data.source)
              )}
            </p>
          )}
          {(message || busy) && (
            <p
              role={failed ? "alert" : "status"}
              className="absolute top-16 right-4 z-10 max-w-[calc(100%-2rem)] rounded-md border border-border bg-surface px-3 py-2 text-sm text-ink shadow-sm"
            >
              {busy ? "Förbereder export…" : message}
            </p>
          )}
        </div>
      </VisualizationPortal.Provider>
    </dialog>
  );
}
