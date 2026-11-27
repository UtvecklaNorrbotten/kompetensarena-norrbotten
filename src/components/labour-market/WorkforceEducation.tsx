import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import matching from "@/data/matching/catalog.json";
import { getMatchingSlice } from "@/lib/aggregates.functions";
import { Select, Figure } from "./WorkforceControls";
import { EmploymentChart } from "./EmploymentCharts";
import snapshot from "@/data/workforce/catalog.json";
import type { WorkforceCatalog } from "@/lib/workforce";
const catalog = snapshot as WorkforceCatalog;
export function EducationBackground({ geo }: { geo: string }) {
  const [group, setGroup] = useState<"inriktning" | "niva" | "grupp">("inriktning");
  const [sex, setSex] = useState<"totalt" | "1" | "2">("totalt");
  const [period, setPeriod] = useState(matching.periods.at(-1)!);
  const [all, setAll] = useState(false);
  const query = useQuery({
    queryKey: ["workforce-education", geo, sex, period],
    queryFn: () => getMatchingSlice({ data: { geo, sex, period, education: "00I" } }),
    staleTime: 3600000,
  });
  const codes: string[] = matching.groups[group];
  const education: Record<string, string> = matching.education;
  const rows = (query.data?.ranking ?? [])
    .filter((r) => codes.includes(r[0]) && !["00I", "00N", "00S"].includes(r[0]))
    .map((r) => ({ label: education[r[0]]!, value: r[7] }))
    .sort((a, b) => (b.value ?? -Infinity) - (a.value ?? -Infinity));
  const source = `Källa: SCB, RMI E3, TAB6929. ${period}. ${catalog.geographies[geo]}. Befolkning 20–69 år, justerat antal personer (E). Uppdaterad ${matching.updated.slice(0, 10)}.`;
  return (
    <Figure
      id="utbildning"
      title="Vilken utbildningsbakgrund har befolkningen?"
      intro={`${catalog.geographies[geo]} · 20–69 år. Detta avsnitt beskriver befolkningens utbildning, inklusive personer utanför arbetskraften.`}
      source={source}
    >
      <div className="mb-6 grid gap-x-5 sm:grid-cols-3">
        <Select
          label="Utbildningsindelning"
          value={group}
          onChange={(v) => setGroup(v as typeof group)}
        >
          <option value="inriktning">Inriktning</option>
          <option value="niva">Nivå</option>
          <option value="grupp">Utbildningsgrupp</option>
        </Select>
        <Select
          label="Kön i utbildningsjämförelsen"
          value={sex}
          onChange={(v) => setSex(v as typeof sex)}
        >
          <option value="totalt">Samtliga</option>
          <option value="2">Kvinnor</option>
          <option value="1">Män</option>
        </Select>
        <Select label="Utbildningens referensår" value={period} onChange={setPeriod}>
          {[...matching.periods].reverse().map((p) => (
            <option key={p}>{p}</option>
          ))}
        </Select>
      </div>
      {query.isPending ? (
        <p role="status">Hämtar utbildningsbakgrund…</p>
      ) : query.isError ? (
        <p role="alert">
          Utbildningsuppgifterna kunde inte läsas.{" "}
          <button className="underline" onClick={() => void query.refetch()}>
            Försök igen
          </button>
        </p>
      ) : (
        <EmploymentChart
          rows={all ? rows : rows.slice(0, 15)}
          rank
          unit="personer"
          name="Personer med utbildningen"
          filename="arbetskraft-utbildningsbakgrund"
          source={source}
        />
      )}
      {rows.length > 15 && (
        <button className="mx-auto mt-6 block underline" onClick={() => setAll(!all)}>
          {all ? "Visa de 15 största" : "Visa alla utbildningsgrupper"}
        </button>
      )}
      <p className="mt-5 text-sm text-ink-muted">
        E3:s justerade befolkningstal är ett annat mått än BAS arbetskraft. Utbildningsgrupp, nivå
        och inriktning har olika avgränsningar. Använd BAS utbildningsnivå ovan för att jämföra
        arbetskraftens antal och deltagande.
      </p>
    </Figure>
  );
}
