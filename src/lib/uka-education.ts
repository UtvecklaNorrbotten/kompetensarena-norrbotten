import type { UkaCatalogEntry, UkaRow } from "@/lib/uka-view";

/** Högsta antal rader i ett serverfunktionssvar för UKÄ-värden. */
export const UKA_SLICE_PAGE_ROWS = 4000;
/** Skydd mot oändliga sidloopar; långt över det största urvalet (cirka 41 000 rader). */
export const UKA_SLICE_MAX_PAGES = 50;

export type UkaSlicePage = {
  rows: { period: string; gender: string; category: string; value: number | null }[];
  next: number | null;
};

export type UkaEducationCatalog = {
  indicators: Record<string, UkaCatalogEntry>;
  /** Uppdelning → kategorier som finns för lärosätet (alla perioder och kön). */
  combos: Record<string, string[]>;
  metadata: { indicator_id: string; tillganglighetsdatum: string | null; hamtad_datum: string | null }[];
};

/**
 * Läs alla sidor av ett urval. Varje svar är begränsat; urvalet blir ändå komplett.
 * Avbryter med fel i stället för att tyst trunkera.
 */
export async function readAllUkaPages(
  fetchPage: (offset: number) => Promise<UkaSlicePage>,
  maxPages = UKA_SLICE_MAX_PAGES,
): Promise<UkaSlicePage["rows"]> {
  const rows: UkaSlicePage["rows"] = [];
  let offset: number | null = 0;
  for (let page = 0; offset !== null; page++) {
    if (page >= maxPages) throw new Error("UKÄ-urvalet kunde inte läsas fullständigt.");
    const result: UkaSlicePage = await fetchPage(offset);
    rows.push(...result.rows);
    if (result.next !== null && result.next <= offset) {
      throw new Error("UKÄ-urvalet kunde inte läsas fullständigt.");
    }
    offset = result.next;
  }
  return rows;
}

export function toUkaRows(
  indicatorId: string,
  university: string,
  breakdown: string,
  rows: UkaSlicePage["rows"],
): UkaRow[] {
  return rows.map((r) => ({
    indicator_id: indicatorId,
    university,
    breakdown,
    period: r.period,
    gender: r.gender,
    category: r.category,
    value: r.value,
  }));
}

/** Kombinationerna som rader för dimensionOptions (endast uppdelning och kategori). */
export function catalogComboRows(combos: UkaEducationCatalog["combos"]) {
  return Object.entries(combos).flatMap(([breakdown, categories]) =>
    categories.map((category) => ({ breakdown, category })),
  );
}
