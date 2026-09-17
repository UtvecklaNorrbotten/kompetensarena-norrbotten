import { exampleIndicators } from "@/data/example-indicators";
import type { Indicator } from "@/data/types";

/**
 * Tunt datalager.
 *
 * Idag läses indikatorer från lokala exempelfiler. När riktiga datakällor
 * (filimport, API, databas) tillkommer byts implementationen här — sidor och
 * komponenter behöver inte ändras eftersom de bara använder funktionerna nedan.
 * Funktionerna är async redan nu just för att kunna bli nätverksanrop senare.
 */

export async function listIndicators(): Promise<Indicator[]> {
  return exampleIndicators;
}

export async function getIndicator(id: string): Promise<Indicator | undefined> {
  return exampleIndicators.find((indicator) => indicator.id === id);
}
