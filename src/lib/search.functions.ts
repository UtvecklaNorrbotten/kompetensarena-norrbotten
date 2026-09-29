import { createServerFn } from "@tanstack/react-start";
import { createClient } from "@supabase/supabase-js";
import { z } from "zod";

export type SearchHit = { kind: string; title: string; description: string | null; url: string };

export const searchSite = createServerFn({ method: "GET" })
  .inputValidator((input: unknown) => z.object({ query: z.string().trim().min(2).max(100) }).parse(input))
  .handler(async ({ data }): Promise<SearchHit[]> => {
    const url = process.env["SUPABASE_URL"];
    const key = process.env["SUPABASE_PUBLISHABLE_KEY"];
    if (!url || !key) throw new Error("Sökningen är inte konfigurerad.");
    const client = createClient(url, key, {
      auth: { persistSession: false },
      global: { fetch: (input, init) => {
        const headers = new Headers(init?.headers);
        if (key.startsWith("sb_") && headers.get("Authorization") === `Bearer ${key}`) headers.delete("Authorization");
        headers.set("apikey", key);
        return fetch(input, { ...init, headers });
      } },
    });
    const { data: hits, error } = await client.rpc("search_site", { query_text: data.query });
    if (error) throw new Error("Sökindexet är inte tillgängligt.");
    return (hits ?? []) as SearchHit[];
  });
