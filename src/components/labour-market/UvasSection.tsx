import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useSearch } from "@tanstack/react-router";
import { AppLink } from "@/components/layout/AppLink";
import { getUvasView } from "@/lib/aggregates.functions";
import { uvasValue } from "@/lib/uvas";
import catalog from "@/data/uvas/catalog.json";
import { UnemploymentChart } from "./UnemploymentChart";
const regions: Record<string, string> = catalog.regions;
const control = "mt-2 w-full rounded-md border border-border bg-surface p-2 text-base";
export function UvasSection() {
  const search = useSearch({ strict: false }) as { geo?: string };
  const geo = search.geo && regions[search.geo] ? search.geo : "25";
  const [age, setAge] = useState<"16-24" | "25-29" | "16-29">("16-29");
  const [sex, setSex] = useState<"Totalt" | "Kvinnor" | "Män">("Totalt");
  const [origin, setOrigin] = useState<"Totalt" | "Inrikesfödd" | "Utrikesfödd">("Totalt");
  const [year, setYear] = useState((catalog.years as string[]).at(-1) ?? "");
  const query = useQuery({
    queryKey: ["uvas", geo, age, sex, origin, year],
    queryFn: () => getUvasView({ data: { geo, age, sex, origin, year } }),
    enabled: !!year,
    staleTime: 3600000,
  });
  const history = query.data?.history ?? [];
  const own = history.find((r) => r.year === year && r.row[0] === geo)?.row;
  const years = catalog.years as string[];
  const timeline = years.length
    ? Array.from({ length: Number(years.at(-1)) - Number(years[0]) + 1 }, (_, i) =>
        String(Number(years[0]) + i),
      )
    : [];
  const points = timeline.map((y) => {
    const row = history.find((r) => r.year === y && r.row[0] === geo)?.row;
    const country = history.find((r) => r.year === y && r.row[0] === "00")?.row;
    return {
      period: y,
      selected: row?.[9] === "observed" ? row[8] : null,
      country: geo === "00" ? null : country?.[9] === "observed" ? country[8] : null,
      selectedSuppressed: row?.[9] === "suppressed",
      countrySuppressed: country?.[9] === "suppressed",
    };
  });
  return (
    <section
      id="uvas"
      className="min-w-0 scroll-mt-28 rounded-xl border border-border bg-surface p-5 md:p-7"
    >
      <h2 className="text-2xl">Hur stor andel unga varken arbetar eller studerar?</h2>
      <p className="mt-3 text-ink-muted">
        MUCF:s registerbaserade UVAS-mått. Årsdata för unga som varken arbetar eller studerar enligt
        MUCF:s definition. Personer i arbetsmarknadsåtgärder kan ingå.
      </p>
      {!year ? (
        <p role="status" className="mt-6">
          MUCF-data väntar på publicering. Statistik visas här när både antal och andelar för en
          fullständigt kontrollerad årgång är publicerade.
        </p>
      ) : (
        <>
          <p className="mt-4">
            {regions[geo]} · År {year}. Andelen avser befolkningen i vald grupp.
          </p>
          <div className="my-5 grid gap-4 sm:grid-cols-2">
            <label>
              Ålder
              <select
                className={control}
                value={age}
                onChange={(e) => setAge(e.target.value as typeof age)}
              >
                {["16-29", "16-24", "25-29"].map((a) => (
                  <option key={a}>{a}</option>
                ))}
              </select>
            </label>
            <label>
              Kön
              <select
                className={control}
                value={sex}
                onChange={(e) => setSex(e.target.value as typeof sex)}
              >
                {["Totalt", "Kvinnor", "Män"].map((s) => (
                  <option key={s}>{s}</option>
                ))}
              </select>
            </label>
            <label>
              Födelseland
              <select
                className={control}
                value={origin}
                onChange={(e) => setOrigin(e.target.value as typeof origin)}
              >
                {["Totalt", "Inrikesfödd", "Utrikesfödd"].map((o) => (
                  <option key={o}>{o}</option>
                ))}
              </select>
            </label>
            <label>
              År
              <select className={control} value={year} onChange={(e) => setYear(e.target.value)}>
                {(catalog.years as string[]).map((y) => (
                  <option key={y}>{y}</option>
                ))}
              </select>
            </label>
          </div>
          {query.isPending ? (
            <p role="status">Hämtar UVAS-statistik…</p>
          ) : query.isError ? (
            <p role="alert">
              Statistiken kunde inte läsas.{" "}
              <button className="underline" onClick={() => void query.refetch()}>
                Försök igen
              </button>
            </p>
          ) : (
            <>
              <div className="my-6 grid gap-4 sm:grid-cols-2">
                <p>
                  Andel:{" "}
                  <strong>
                    {uvasValue(own?.[8], own?.[9])}
                    {typeof own?.[8] === "number" ? " %" : ""}
                  </strong>
                </p>
                <p>
                  Antal: <strong>{uvasValue(own?.[5], own?.[6])}</strong>
                </p>
              </div>
              <UnemploymentChart
                title="Andel unga som varken arbetar eller studerar enligt MUCF"
                name={regions[geo] ?? geo}
                unit="%"
                rows={points}
              />
              <div className="mt-7 overflow-x-auto">
                <table className="w-full text-sm">
                  <caption className="mb-3 text-left">
                    Geografisk jämförelse · {year} · {age} år · {sex} · {origin}
                  </caption>
                  <thead>
                    <tr>
                      <th className="p-2 text-left">Geografi</th>
                      <th>Andel (%)</th>
                      <th>Antal</th>
                    </tr>
                  </thead>
                  <tbody>
                    {(query.data?.comparison ?? [])
                      .filter(
                        (r) =>
                          r[0].length === 2 ||
                          r[0].startsWith(
                            geo.length === 4 ? geo.slice(0, 2) : geo === "00" ? "25" : geo,
                          ),
                      )
                      .map((r) => (
                        <tr key={r[0]} className="border-t border-border">
                          <th className="p-2 text-left font-normal">
                            <AppLink
                              href={`/omraden/arbetsmarknad/arbetsloshet?geo=${r[0]}`}
                              className="underline"
                            >
                              {regions[r[0]] ?? r[0]}
                            </AppLink>
                          </th>
                          <td className="text-center">{uvasValue(r[8], r[9])}</td>
                          <td className="text-center">{uvasValue(r[5], r[6])}</td>
                        </tr>
                      ))}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </>
      )}
      <div className="mt-6 space-y-3 border-t border-border pt-4 text-sm text-ink-muted">
        <p>
          Observerad noll visas som 0. Prickade värden visas som Sekretess; tomma värden som Uppgift
          saknas. Publicerade totaler och andelar används direkt.
        </p>
        <p>
          Från 2023 används CKM, vilket kan ge skillnader mellan delar och totaler. Från 2015 räknas
          gränspendling till Finland bort. Jämförelser över dessa år kräver försiktighet, särskilt i
          Norrbotten.
        </p>
        <p>
          UVAS är årsstatistik och följer MUCF:s definition. Det ska inte tolkas som
          Arbetsförmedlingens inskrivna arbetslöshet. Tolvmånadersmedel används inte här.
        </p>
        <a href={catalog.source} className="underline" target="_blank" rel="noreferrer">
          Källa och definition: MUCF
        </a>
      </div>
    </section>
  );
}
