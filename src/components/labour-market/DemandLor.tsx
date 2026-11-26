import { useQuery } from "@tanstack/react-query";
import { getDemandLor } from "@/lib/aggregates.functions";
import { demandNumber, type DemandRank } from "@/lib/labour-demand";
import { DemandRanking, DemandTimeChart } from "./DemandCharts";
import { useState } from "react";
export function DemandLor({ geo, name }: { geo: string; name: string }) {
  const [grouping, setGrouping] = useState("grouped");
  const [kind, setKind] = useState("LJtot");
  const query = useQuery({
    queryKey: ["demand-lor", geo],
    queryFn: () => getDemandLor({ data: { geo } }),
    staleTime: 3600000,
  });
  const vacancies = query.data?.find((d) => d.table === "TAB6606");
  const shortage = query.data?.find((d) => d.table === "TAB6989");
  const periods = [...new Set(vacancies?.records.map((r) => String(r["Tid"])) ?? [])].sort();
  const number = (row: Record<string, string | number | null> | undefined) =>
    typeof row?.["value"] === "number" ? row["value"] : null;
  const rows = periods.map((period) => ({
    period,
    value: number(
      vacancies?.records.find(
        (r) => r["Tid"] === period && r["LedJobbTyp"] === kind && r["ContentsCode"] === "0000081D",
      ),
    ),
    margin: number(
      vacancies?.records.find(
        (r) => r["Tid"] === period && r["LedJobbTyp"] === kind && r["ContentsCode"] === "0000081E",
      ),
    ),
  }));
  const year = [...new Set(shortage?.records.map((r) => String(r["Tid"])) ?? [])].sort().at(-1);
  const occupations = shortage?.labels["Yrke"] as Record<string, string> | undefined;
  const ranks: DemandRank[] = Object.entries(occupations ?? {})
    .filter(([code]) =>
      grouping === "grouped"
        ? ["gr1", "gr2-3", "gr4-8", "gr9"].includes(code)
        : /^[1-9]$/.test(code),
    )
    .map(([code, label]) => ({
      code,
      label,
      value: number(
        shortage?.records.find(
          (r) => r["Tid"] === year && r["Yrke"] === code && r["ContentsCode"] === "000008UB",
        ),
      ),
      previous: null,
      change: null,
    }));
  return (
    <section
      id="lor"
      className="scroll-mt-28 rounded-xl border border-border bg-surface p-5 md:p-7"
    >
      <h2 className="text-2xl">Hur stor är efterfrågan även utanför Platsbanken?</h2>
      <p className="mt-3 leading-relaxed text-ink-muted">
        SCB:s Lediga jobb och rekryteringsbehov (LoR) bygger på en arbetsgivarundersökning och
        omfattar också jobb utan annons. Här visas {name}. Kommunuppgifter finns inte. Yrkesfilter
        och månad ovanför gäller AF:s statistik och påverkar inte denna del.
      </p>
      {query.isError ? (
        <p role="alert" className="mt-5">
          Kunde inte läsa SCB-statistiken.{" "}
          <button className="underline" onClick={() => void query.refetch()}>
            Försök igen
          </button>
        </p>
      ) : query.isPending ? (
        <p className="py-8" role="status">
          Läser SCB-statistik…
        </p>
      ) : (
        <>
          <label className="mt-6 block text-sm">
            Typ av lediga jobb
            <select
              value={kind}
              onChange={(e) => setKind(e.target.value)}
              className="mt-2 block w-full rounded-md border border-border bg-surface p-3"
            >
              {Object.entries(vacancies?.labels["LedJobbTyp"] ?? {}).map(([code, label]) => (
                <option value={code} key={code}>
                  {label}
                </option>
              ))}
            </select>
          </label>
          <div className="mt-6">
            <DemandTimeChart rows={rows} name={name} unit="jobb" />
          </div>
          <p className="mt-4 text-sm text-ink-muted">
            Felstaplar visar SCB:s osäkerhetsmarginal. Skattningar är avrundade till hundratal.
            Undertryckta värden visas som uppgift saknas; ett redovisat nollvärde kan bero på
            avrundning. LoR börjar 2024K2. Äldre KV fogas inte till serien på grund av metodbrott.
          </p>
          <h3 className="mt-10 text-xl">Inom vilka yrkesområden saknar arbetsgivarna personal?</h3>
          <p className="my-4 text-sm text-ink-muted">
            {name}, {year}. Personer som saknas där arbete inte blir utfört trots möjlighet att
            anställa. Avser arbetsställen med minst fem anställda. Detta är ett annat mått än lediga
            jobb.
          </p>
          <label className="my-5 block text-sm">
            Yrkesindelning
            <select
              className="mt-2 block w-full rounded-md border border-border bg-surface p-3"
              value={grouping}
              onChange={(e) => setGrouping(e.target.value)}
            >
              <option value="grouped">Fyra grupper efter vanlig kompetensnivå</option>
              <option value="detailed">Nio yrkesområden (SSYK 2012)</option>
            </select>
          </label>
          <p className="my-4 text-sm text-ink-muted">
            Grövre grupper kan ge fler redovisade skattningar. Uppgift saknas när SCB inte redovisar
            ett värde; det betyder inte noll. Gruppernas värden och marginaler hämtas direkt från
            SCB och summeras inte från de nio yrkesområdena. Andelar publiceras ännu inte av SCB i
            TAB6989.
          </p>
          <DemandRanking key={grouping} rows={ranks} unit="personer" allowChange={false} />
          <details className="mt-5 text-sm">
            <summary className="cursor-pointer text-brand-dark">
              Skattningar och osäkerhetsmarginaler
            </summary>
            <div className="overflow-auto">
              <table className="mt-3 w-full">
                <thead>
                  <tr>
                    <th scope="col" className="text-left">
                      SSYK 2012, yrkesområde
                    </th>
                    <th scope="col">Antal</th>
                    <th scope="col">Marginal ±</th>
                  </tr>
                </thead>
                <tbody>
                  {ranks.map((r) => (
                    <tr className="border-t border-border" key={r.code}>
                      <th scope="row" className="p-2 text-left font-normal">
                        {r.label}
                      </th>
                      <td className="p-2 text-center">{demandNumber(r.value)}</td>
                      <td className="p-2 text-center">
                        {demandNumber(
                          number(
                            shortage?.records.find(
                              (v) =>
                                v["Tid"] === year &&
                                v["Yrke"] === r.code &&
                                v["ContentsCode"] === "000008UC",
                            ),
                          ),
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </details>
          <p className="mt-6 border-t border-border pt-4 text-sm text-ink-muted">
            <a
              href="https://www.scb.se/am0702"
              className="underline"
              target="_blank"
              rel="noreferrer"
            >
              Källa: SCB, LoR
            </a>{" "}
            · TAB6606, {periods[0]}–{periods.at(-1)}, uppdaterad {vacancies?.updated.slice(0, 10)}.
            TAB6989, {year}, uppdaterad {shortage?.updated.slice(0, 10)}.
          </p>
        </>
      )}
    </section>
  );
}
