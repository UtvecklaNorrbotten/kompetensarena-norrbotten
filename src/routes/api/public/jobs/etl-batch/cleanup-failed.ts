import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/public/jobs/etl-batch/cleanup-failed")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { handleBatchCleanupFailed } = await import("@/lib/etl-batch.server");
        return handleBatchCleanupFailed(request);
      },
    },
  },
});
