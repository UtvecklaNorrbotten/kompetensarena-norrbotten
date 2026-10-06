import { CircleHelp } from "lucide-react";
import { Popover, PopoverContent, PopoverTrigger } from "./popover";

/** Begreppshjälp som fungerar med mus, tangentbord och pekskärm. */
export function ExplainedTerm({ term, explanation }: { term: string; explanation: string }) {
  return (
    <Popover>
      <PopoverTrigger asChild>
        <button
          type="button"
          className="group relative inline cursor-help border-b border-dashed border-current text-left font-inherit"
          aria-label={`Förklara ${term}`}
        >
          {term}
          <CircleHelp
            aria-hidden
            className="pointer-events-none absolute -right-4 -top-2 size-3.5 bg-surface text-brand-dark opacity-0 group-hover:opacity-100 group-focus-visible:opacity-100"
          />
        </button>
      </PopoverTrigger>
      <PopoverContent
        className="w-[min(340px,calc(100vw-32px))] font-normal leading-relaxed"
        side="top"
      >
        <p className="mb-2 font-semibold text-brand-dark">{term}</p>
        <p className="text-base">{explanation}</p>
        <a
          className="mt-3 block text-xs text-brand-dark underline"
          href="https://www.uka.se/statistik-och-analys/om-var-statistik/information-om-statistiken"
          target="_blank"
          rel="noreferrer"
        >
          Om UKÄ:s statistik
        </a>
      </PopoverContent>
    </Popover>
  );
}
