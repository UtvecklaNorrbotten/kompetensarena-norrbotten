import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/public/jobs/etl-batch/cleanup-failed")({
  server: {
    handlers: {
      GET: async ({ request }) => {
        const { handleBatchListFailed } = await import("@/lib/etl-batch.server");
        return handleBatchListFailed(request);
      },
      POST: async ({ request }) => {
        const { handleBatchCleanupFailed } = await import("@/lib/etl-batch.server");
        return handleBatchCleanupFailed(request);
      },
    },
  },
});
