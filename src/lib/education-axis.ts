/** Gemensam, avrundad skala för båda terminsdiagrammen. */
export function educationAxis(values: number[], unit: string) {
  if (unit === "%") return { maximum: 100, ticks: [0, 20, 40, 60, 80, 100] };
  const largest = values.reduce(
    (max, value) => (Number.isFinite(value) ? Math.max(max, value) : max),
    0,
  );
  const decimal = unit === "sökande per antagen";
  const target = Math.max(1, largest * 1.05);
  const rawStep = target / 4;
  const power = 10 ** Math.floor(Math.log10(rawStep));
  const multiples = [1, 2, 5, 10];
  const multiple = multiples.find((value) => value * power >= rawStep) ?? 10;
  // Antal får heltalssteg; söktryck får decimalsteg som går att visa med en decimal.
  const step = Math.max(decimal ? 0.1 : 1, multiple * power);
  const intervals = Math.ceil(target / step);
  const ticks = Array.from({ length: intervals + 1 }, (_, i) => Number((i * step).toPrecision(12)));
  return { maximum: ticks.at(-1) ?? 1, ticks };
}
