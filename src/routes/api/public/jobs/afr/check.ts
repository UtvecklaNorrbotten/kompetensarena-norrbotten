import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/public/jobs/afr/check")({
  server: {
    handlers: {
      POST: async ({ request }) => (await import("@/lib/afr-etl.server")).handleAfrCheck(request),
    },
  },
});
