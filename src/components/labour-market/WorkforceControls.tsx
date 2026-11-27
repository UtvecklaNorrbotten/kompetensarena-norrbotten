import { useId, type ReactNode } from "react";
export function Select({
  label,
  value,
  onChange,
  children,
}: {
  label: string;
  value: string;
  onChange: (s: string) => void;
  children: ReactNode;
}) {
  const id = useId();
  return (
    <div className="mt-5 min-w-0">
      <label htmlFor={id} className="block text-sm font-semibold">
        {label}
      </label>
      <select
        id={id}
        className="mt-2 w-full min-w-0 rounded-md border border-border bg-surface p-2 text-base font-normal"
        value={value}
        onChange={(e) => onChange(e.target.value)}
      >
        {children}
      </select>
    </div>
  );
}
export function Figure({
  id,
  title,
  intro,
  source,
  children,
}: {
  id: string;
  title: string;
  intro: string;
  source: string;
  children: ReactNode;
}) {
  return (
    <section
      id={id}
      className="min-w-0 scroll-mt-28 rounded-xl border border-border bg-surface p-5 md:p-8"
    >
      <h2 className="text-2xl md:text-3xl">{title}</h2>
      <p className="mb-6 mt-3 leading-relaxed text-ink-muted">{intro}</p>
      {children}
      <p className="mt-6 border-t border-border pt-4 text-sm text-ink-muted">{source}</p>
    </section>
  );
}
