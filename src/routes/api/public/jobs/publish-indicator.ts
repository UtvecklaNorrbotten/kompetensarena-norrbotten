import { createFileRoute } from "@tanstack/react-router";

/**
 * ETL-endpoint för schemalagda dataimporter (GitHub Actions).
 * All logik ligger i etl-publish.server.ts och laddas först inne i handlern.
 */
export const Route = createFileRoute("/api/public/jobs/publish-indicator")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { handleEtlPublish } = await import("@/lib/etl-publish.server");
        return handleEtlPublish(request);
      },
    },
  },
});
