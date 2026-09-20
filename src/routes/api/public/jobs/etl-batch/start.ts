import { createFileRoute } from "@tanstack/react-router";

/** Startar en chunkad ETL-batch. Logiken laddas först inne i handlern. */
export const Route = createFileRoute("/api/public/jobs/etl-batch/start")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { handleBatchStart } = await import("@/lib/etl-batch.server");
        return handleBatchStart(request);
      },
    },
  },
});
