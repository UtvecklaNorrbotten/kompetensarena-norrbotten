import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";

/**
 * Laddningsskelett för visualiseringar.
 * Har samma yttermått som det färdiga innehållet så att sidan inte hoppar,
 * annonseras för skärmläsare via role="status" och respekterar
 * prefers-reduced-motion (pulseringen stängs av).
 */

function LoadingRegion({
  label,
  className,
  children,
}: {
  label: string;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <div
      role="status"
      aria-live="polite"
      aria-busy="true"
      className={cn("motion-reduce:[&_*]:animate-none", className)}
    >
      <span className="sr-only">{label}</span>
      <div aria-hidden="true">{children}</div>
    </div>
  );
}

export function KpiCardSkeleton({ className }: { className?: string }) {
  return (
    <LoadingRegion label="Laddar nyckeltal…" className={cn("rounded-lg border bg-card p-5", className)}>
      <Skeleton className="h-4 w-2/3" />
      <Skeleton className="mt-4 h-9 w-1/2" />
      <Skeleton className="mt-3 h-3 w-1/3" />
    </LoadingRegion>
  );
}

export function KpiGridSkeleton({ count = 4 }: { count?: number }) {
  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
      {Array.from({ length: count }, (_, i) => (
        <KpiCardSkeleton key={i} />
      ))}
    </div>
  );
}

const BAR_HEIGHTS = [45, 62, 38, 70, 55, 80, 66, 48, 74, 58, 85, 60];

export function ChartSkeleton({
  height = 320,
  className,
}: {
  height?: number;
  className?: string;
}) {
  return (
    <LoadingRegion label="Laddar diagram…" className={cn("rounded-lg border bg-card p-5", className)}>
      <Skeleton className="h-5 w-1/3" />
      <Skeleton className="mt-2 h-3 w-1/2" />
      <div className="mt-6 flex items-end gap-2" style={{ height }}>
        {BAR_HEIGHTS.map((h, i) => (
          <Skeleton key={i} className="flex-1 rounded-sm" style={{ height: `${h}%` }} />
        ))}
      </div>
      <Skeleton className="mt-4 h-3 w-1/4" />
    </LoadingRegion>
  );
}

export function TableSkeleton({ rows = 6, columns = 4 }: { rows?: number; columns?: number }) {
  return (
    <LoadingRegion label="Laddar tabell…" className="rounded-lg border bg-card p-5">
      <div className="grid gap-3" style={{ gridTemplateColumns: `repeat(${columns}, minmax(0, 1fr))` }}>
        {Array.from({ length: columns }, (_, i) => (
          <Skeleton key={`h${i}`} className="h-4 w-3/4" />
        ))}
        {Array.from({ length: rows * columns }, (_, i) => (
          <Skeleton key={i} className="h-3.5 w-full" />
        ))}
      </div>
    </LoadingRegion>
  );
}
