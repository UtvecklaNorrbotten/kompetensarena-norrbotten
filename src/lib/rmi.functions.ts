import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import type { RmiRow } from "./rmi";

// Public SCB snapshots are already aggregated. No raw observations or personal records.
const snapshots = import.meta.glob<{ default: RmiRow[] }>("../data/rmi/25*.json");
const geo = z.string().regex(/^25(\d{2})?$/);
export const getRmiRows = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) =>
    z.object({ geo, sex: z.enum(["totalt", "1", "2"]) }).parse(input),
  )
  .handler(async ({ data }) => {
    const loader = snapshots[`../data/rmi/${data.geo}.json`];
    if (!loader) throw new Error("Statistik saknas för den valda kommunen.");
    return (await loader()).default.filter((r) => r[1] === data.sex);
  });
export const getRmiComparison = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) =>
    z
      .object({
        group: z.string().regex(/^[A-Z0-9+]{1,12}$/),
        sex: z.enum(["totalt", "1", "2"]),
        period: z.string().regex(/^\d{4}-\d{4}$/),
      })
      .parse(input),
  )
  .handler(async ({ data }) =>
    Promise.all(
      Object.entries(snapshots).map(async ([path, loader]) => ({
        geo: path.match(/\/(25\d*)\.json$/)![1]!,
        row:
          (await loader()).default.find(
            (r) => r[0] === data.group && r[1] === data.sex && r[2] === data.period,
          ) ?? null,
      })),
    ),
  );
