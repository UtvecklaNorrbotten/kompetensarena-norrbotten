import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/public/jobs/etl-state")({
  server: {
    handlers: {
      GET: async ({ request }) => {
        const { handleEtlState } = await import("@/lib/etl-state.server");
        return handleEtlState(request);
      },
    },
  },
});
