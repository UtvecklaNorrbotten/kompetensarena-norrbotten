/** Heltalsaxel med noll, jämna steg och minst ett helt steg ovanför högsta värdet. */
export function countAxis(values: number[]) {
  const finite = values.filter(Number.isFinite);
  const low = Math.min(0, ...finite);
  const high = Math.max(0, ...finite);
  if (low === 0 && high === 0)
    return { minimum: 0, maximum: 5, step: 1, ticks: [0, 1, 2, 3, 4, 5] };
  const rawStep = (high - low) / 5;
  const power = 10 ** Math.floor(Math.log10(rawStep));
  const multiple = [1, 2, 5, 10].find((n) => n * power >= rawStep) ?? 10;
  const step = Math.max(1, multiple * power);
  const first = low < 0 ? Math.floor(low / step) - 1 : 0;
  const last = high > 0 ? Math.ceil(high / step) + 1 : 0;
  const ticks = Array.from({ length: last - first + 1 }, (_, i) =>
    Number(((first + i) * step).toPrecision(12)),
  );
  return { minimum: ticks[0]!, maximum: ticks.at(-1)!, step, ticks };
}

/** Samma skala för utbildningssidans tidsserier och fördjupningar. */
export function educationAxis(values: number[], unit: string) {
  if (unit === "%") return { minimum: 0, maximum: 100, step: 20, ticks: [0, 20, 40, 60, 80, 100] };
  return countAxis(values);
}
