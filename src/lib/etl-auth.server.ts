/**
 * Delad autentisering och skydd för ETL-endpoints.
 *
 * Nyckeln (`ETL_PUBLISH_KEY`, med valfri `ETL_PUBLISH_KEY_PREVIOUS` under
 * nyckelbyte) finns bara som hemlighet i Lovable och i GitHub Actions Secrets —
 * aldrig i repot, aldrig i klientkod, aldrig i databasen och aldrig i loggar.
 */

export function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

/** Enkel takbegränsning per serverinstans (best effort). */
export function createRateLimiter(max: number, windowMs = 60_000) {
  const hits: number[] = [];
  return function rateLimited(): boolean {
    const now = Date.now();
    while (hits.length && now - hits[0]! > windowMs) hits.shift();
    if (hits.length >= max) return true;
    hits.push(now);
    return false;
  };
}

export async function authorize(request: Request): Promise<Response | null> {
  const current = process.env["ETL_PUBLISH_KEY"];
  const previous = process.env["ETL_PUBLISH_KEY_PREVIOUS"];

  if (!current) {
    console.error("[etl] ETL_PUBLISH_KEY saknas i miljön");
    return json({ error: "Server configuration error" }, 500);
  }

  const header = request.headers.get("authorization") ?? "";
  const token = /^Bearer ([^\s,]+)$/.exec(header)?.[1];
  if (!token) return json({ error: "Unauthorized" }, 401);

  const { createHash, timingSafeEqual } = await import("node:crypto");
  const digest = (v: string) => createHash("sha256").update(v, "utf8").digest();
  const provided = digest(token);
  const ok =
    timingSafeEqual(provided, digest(current)) ||
    timingSafeEqual(provided, digest(previous ?? current));

  // Loggar aldrig nyckeln eller det inskickade värdet.
  if (!ok) return json({ error: "Forbidden" }, 403);
  return null;
}
