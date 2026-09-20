import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/public/jobs/etl-no-change")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { handleEtlNoChange } = await import("@/lib/etl-state.server");
        return handleEtlNoChange(request);
      },
    },
  },
});
