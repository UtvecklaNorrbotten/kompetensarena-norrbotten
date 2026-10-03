import { z } from "zod";

/**
 * Geografiskt urval för visualiseringar.
 * Norrbottens län är förval tills besökaren väljer något annat.
 * Urvalet bärs i URL:en (?geo=) så att länkar kan delas.
 * Själva filterkontrollen visas först när det finns visualiseringar.
 */
export const DEFAULT_GEO_CODE = "25";

export const geoSearchSchema = z.object({
  geo: z
    .string()
    .regex(/^(00|\d{2}|\d{4})$/)
    .catch(DEFAULT_GEO_CODE)
    .default(DEFAULT_GEO_CODE),
});

export type GeoSearch = z.infer<typeof geoSearchSchema>;
