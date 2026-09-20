import { createFileRoute } from "@tanstack/react-router";

/** Finaliserar en ETL-batch atomiskt. */
export const Route = createFileRoute("/api/public/jobs/etl-batch/finalize")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { handleBatchFinalize } = await import("@/lib/etl-batch.server");
        return handleBatchFinalize(request);
      },
    },
  },
});
