import { createFileRoute } from "@tanstack/react-router";

/** Avbryter en pågående ETL-batch och rensar stagingdata. */
export const Route = createFileRoute("/api/public/jobs/etl-batch/abort")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { handleBatchAbort } = await import("@/lib/etl-batch.server");
        return handleBatchAbort(request);
      },
    },
  },
});
