import { getIndicatorFn, listIndicatorsFn } from "@/lib/indicators.functions";
import type { Indicator } from "@/data/types";

/**
 * Tunt datalager.
 *
 * Indikatorer läses från databasen via serverfunktioner (RLS styr synlighet).
 * Webbplatsen anropar aldrig externa datakällor vid sidladdning — allt data
 * kommer från vår egen lagring, som ETL-flödet (GitHub Actions + R) fyller på.
 * Funktionerna är async och kan byta implementation utan att sidorna ändras.
 */

export async function listIndicators(): Promise<Indicator[]> {
  return listIndicatorsFn();
}

export async function getIndicator(id: string): Promise<Indicator | undefined> {
  return getIndicatorFn({ data: { id } });
}
