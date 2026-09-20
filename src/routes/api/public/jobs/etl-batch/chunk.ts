import { createFileRoute } from "@tanstack/react-router";

/** Tar emot en chunk till en pågående ETL-batch. */
export const Route = createFileRoute("/api/public/jobs/etl-batch/chunk")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { handleBatchChunk } = await import("@/lib/etl-batch.server");
        return handleBatchChunk(request);
      },
    },
  },
});
