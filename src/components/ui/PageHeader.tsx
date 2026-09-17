type PageHeaderProps = {
  eyebrow?: string;
  title: string;
  intro?: string;
};

export function PageHeader({ eyebrow, title, intro }: PageHeaderProps) {
  return (
    <div className="max-w-(--container-prose)">
      {eyebrow && (
        <p className="mb-3 text-sm uppercase tracking-[0.18em] text-ink-muted">
          {eyebrow}
        </p>
      )}
      <h1 className="text-balance text-4xl leading-tight md:text-5xl">{title}</h1>
      {intro && <p className="mt-5 text-lg leading-relaxed text-ink">{intro}</p>}
    </div>
  );
}
