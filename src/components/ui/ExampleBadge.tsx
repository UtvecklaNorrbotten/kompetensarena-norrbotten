/** Märker tydligt att innehållet är påhittad exempeldata. */
export function ExampleBadge({ children = "Exempeldata" }: { children?: string }) {
  return (
    <span className="inline-flex items-center rounded-full bg-accent-orange-light px-3 py-1 text-sm text-ink">
      {children}
    </span>
  );
}
