import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/public/jobs/afr/start")({
  server: {
    handlers: {
      POST: async ({ request }) => (await import("@/lib/afr-etl.server")).handleAfrStart(request),
    },
  },
});
