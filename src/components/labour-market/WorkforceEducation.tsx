import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { getWorkforceSlice } from "@/lib/aggregates.functions";
import { Select, Figure } from "./WorkforceControls";
import { EmploymentChart } from "./EmploymentCharts";
import snapshot from "@/data/workforce/catalog.json";
import { workforcePoint, workforceValue, type WorkforceCatalog } from "@/lib/workforce";
const catalog = snapshot as WorkforceCatalog;
export function EducationBackground({ geo }: { geo: string }) {
  const info = catalog.datasets["rmi-education"]!;
  const [group, setGroup] = useState("inriktning");
  const [sex, setSex] = useState("totalt");
  const [period, setPeriod] = useState(info.periods.at(-1)!);
  const [all, setAll] = useState(false);
  const effectiveGeo = info.selection["Region"]!.includes(geo) ? geo : geo.slice(0, 2);
  const query = useQuery({
    queryKey: ["workforce", "rmi-education", effectiveGeo],
    queryFn: () => getWorkforceSlice({ data: { dataset: "rmi-education", geo: effectiveGeo } }),
    staleTime: 3600000,
  });
  const codes = info.groups?.[group] ?? [];
  const measure = Object.entries(info.measures).find(([, l]) => l === "I arbetskraften")![0];
  const rows = codes
    .filter((c) => c in info.categories && !["00I", "00N", "00S"].includes(c))
    .map((c) => {
      const r = workforcePoint(query.data ?? [], period, sex, c, "", measure);
      return { label: info.categories[c]!, value: workforceValue(r), status: r?.[6] ?? "" };
    })
    .sort((a, b) => (b.value ?? -Infinity) - (a.value ?? -Infinity));
  const source = `Källa: SCB, RMI U1b, TAB6368. ${period}. ${catalog.geographies[effectiveGeo]}. Arbetskraft 20–64 år enligt RMI. Källa uppdaterad ${info.updated.slice(0, 10)}.`;
  return (
    <Figure
      id="utbildning"
      title="Hur är arbetskraften fördelad efter utbildning?"
      intro={`${catalog.geographies[effectiveGeo]} · 20–64 år. RMI kombinerar förvärvsarbetande och inskrivna arbetslösa hos Arbetsförmedlingen.`}
      source={source}
    >
      {geo !== effectiveGeo && (
        <p className="mb-5 text-sm text-ink-muted">
          Detta underlag saknar kommunuppgifter. Här visas {catalog.geographies[effectiveGeo]}.
        </p>
      )}
      <div className="mb-6 grid gap-x-5 sm:grid-cols-3">
        <Select label="Utbildningsindelning" value={group} onChange={setGroup}>
          <option value="inriktning">Inriktning</option>
          <option value="niva">Nivå</option>
          <option value="grupp">Utbildningsgrupp</option>
        </Select>
        <Select label="Kön i utbildningsjämförelsen" value={sex} onChange={setSex}>
          <option value="totalt">Samtliga</option>
          <option value="2">Kvinnor</option>
          <option value="1">Män</option>
        </Select>
        <Select label="Utbildningens referensår" value={period} onChange={setPeriod}>
          {[...info.periods].reverse().map((p) => (
            <option key={p}>{p}</option>
          ))}
        </Select>
      </div>
      {query.isPending ? (
        <p role="status">Hämtar arbetskraft efter utbildning…</p>
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
          name="Personer i arbetskraften enligt RMI"
          filename="arbetskraft-utbildning"
          source={source}
        />
      )}
      {rows.length > 15 && (
        <button className="mx-auto mt-6 block underline" onClick={() => setAll(!all)}>
          {all ? "Visa de 15 största" : "Visa alla utbildningsgrupper"}
        </button>
      )}
      <p className="mt-5 text-sm text-ink-muted">
        RMI:s arbetskraftsmått har en annan arbetslöshetsdefinition än BAS. Uppgifterna beskriver
        boende i området; U4 beskriver i stället arbetsplatsens län. Utbildningsgrupp, nivå och
        inriktning visas separat. Serien har källbyte 2022. Välj RMI U1b i underlagsfiltret för att
        se historiken.
      </p>
    </Figure>
  );
}
