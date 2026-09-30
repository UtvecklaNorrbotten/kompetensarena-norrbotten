import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/public/jobs/etl-batch/resume-history")({
  server: {
    handlers: {
      GET: async ({ request }) => {
        const { handleBatchResumeHistory } = await import("@/lib/etl-batch.server");
        return handleBatchResumeHistory(request);
      },
      POST: async ({ request }) => {
        const { handleBatchResumeHistory } = await import("@/lib/etl-batch.server");
        return handleBatchResumeHistory(request);
      },
    },
  },
});
