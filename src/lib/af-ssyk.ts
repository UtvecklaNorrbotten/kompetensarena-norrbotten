/** AF-SSYK: classify each source row once; 9999 and missing codes are residuals. */
export const afSsykFour: Record<string, string> = {
  "four:1": "Chefsyrken",
  "four:2-3": "Yrken som vanligtvis kräver eftergymnasial kompetens",
  "four:4-8": "Yrken som vanligtvis kräver gymnasial kompetens eller motsvarande",
  "four:9": "Yrken med krav på kortare utbildning eller introduktion",
  "other:military": "Militära yrken",
  "other:unknown": "Okänt yrke",
};
export const afSsykNine: Record<string, string> = {
  "nine:1": "Chefsyrken",
  "nine:2": "Yrken med krav på fördjupad högskolekompetens",
  "nine:3": "Yrken med krav på högskolekompetens eller motsvarande",
  "nine:4": "Yrken inom administration och kundtjänst",
  "nine:5": "Service-, omsorgs- och försäljningsyrken",
  "nine:6": "Yrken inom lantbruk, trädgård, skogsbruk och fiske",
  "nine:7": "Yrken inom byggverksamhet och tillverkning",
  "nine:8": "Yrken inom maskinell tillverkning och transport m.m.",
  "nine:9": "Yrken med krav på kortare utbildning eller introduktion",
  "other:military": "Militära yrken",
  "other:unknown": "Okänt yrke",
};
export function afSsykCategory(code: string, level: "four" | "nine"): string {
  if (!/^\d{4}$/.test(code) || code === "9999") return "other:unknown";
  const first = Number(code[0]);
  if (first === 0) return "other:military";
  return level === "nine"
    ? `nine:${first}`
    : first === 1
      ? "four:1"
      : first <= 3
        ? "four:2-3"
        : first <= 8
          ? "four:4-8"
          : "four:9";
}
export function afSsykMatches(code: string, selection: string) {
  if (selection.startsWith("four:")) return afSsykCategory(code, "four") === selection;
  if (selection.startsWith("nine:")) return afSsykCategory(code, "nine") === selection;
  if (selection.startsWith("other:")) return afSsykCategory(code, "four") === selection;
  return code === selection;
}
