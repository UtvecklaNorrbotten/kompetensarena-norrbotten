import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/public/jobs/afr/resume")({
  server: {
    handlers: {
      GET: async ({ request }) => (await import("@/lib/afr-etl.server")).handleAfrResume(request),
      POST: async ({ request }) => (await import("@/lib/afr-etl.server")).handleAfrResume(request),
    },
  },
});
