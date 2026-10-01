import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/public/jobs/afr/chunk")({
  server: {
    handlers: {
      POST: async ({ request }) => (await import("@/lib/afr-etl.server")).handleAfrChunk(request),
    },
  },
});
