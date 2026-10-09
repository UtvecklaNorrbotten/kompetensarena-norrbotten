/** Gemensam, avrundad skala för båda terminsdiagrammen. */
export function educationAxis(values: number[], unit: string) {
  if (unit === "%") return { maximum: 100, ticks: [0, 20, 40, 60, 80, 100] };
  const largest = values.reduce(
    (max, value) => (Number.isFinite(value) ? Math.max(max, value) : max),
    0,
  );
  const target = Math.max(1, largest * 1.05);
  const rawStep = target / 4;
  const power = 10 ** Math.floor(Math.log10(rawStep));
  const multiples = [1, 2, 5, 10];
  const multiple = multiples.find((value) => value * power >= rawStep) ?? 10;
  // Axelmarkeringarna är heltal även när källvärdena har decimaler.
  const step = Math.max(1, multiple * power);
  const intervals = Math.ceil(target / step);
  const ticks = Array.from({ length: intervals + 1 }, (_, i) => Number((i * step).toPrecision(12)));
  return { maximum: ticks.at(-1) ?? 1, ticks };
}
