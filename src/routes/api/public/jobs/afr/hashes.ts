import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/public/jobs/afr/hashes")({
  server: {
    handlers: {
      GET: async ({ request }) => (await import("@/lib/afr-etl.server")).handleAfrHashes(request),
    },
  },
});
