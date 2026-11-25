export type RmiRow = [
  group: string,
  sex: string,
  period: string,
  start: number | null,
  end: number | null,
  net: number | null,
  ageIn: number | null,
  ageOut: number | null,
  moveIn: number | null,
  moveOut: number | null,
  graduates: number | null,
  further: number | null,
];
export const flowPairs = [
  {
    label: "Flyttningar",
    incoming: 8,
    outgoing: 9,
    inLabel: "Inflyttade",
    outLabel: "Utflyttade, inklusive avlidna",
  },
  {
    label: "Ny utbildning",
    incoming: 10,
    outgoing: 11,
    inLabel: "Till gruppen genom utbildning",
    outLabel: "Från gruppen genom vidareutbildning",
  },
  {
    label: "Åldersgränser",
    incoming: 6,
    outgoing: 7,
    inLabel: "In i åldersgruppen",
    outLabel: "Ut ur åldersgruppen",
  },
] as const;
export const rmiNumber = (v: unknown) =>
  typeof v === "number" && Number.isFinite(v) ? v.toLocaleString("sv-SE") : "Uppgift saknas";
export function selectRmi(rows: RmiRow[], group: string, sex: string, period?: string) {
  return rows
    .filter((r) => r[0] === group && r[1] === sex && (!period || r[2] === period))
    .sort((a, b) => a[2].localeCompare(b[2]));
}
