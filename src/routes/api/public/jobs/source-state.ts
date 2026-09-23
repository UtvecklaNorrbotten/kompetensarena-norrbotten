import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/public/jobs/source-state")({
  server: {
    handlers: {
      GET: async ({ request }) => {
        const { handleSourceStateGet } = await import("@/lib/etl-source-state.server");
        return handleSourceStateGet(request);
      },
      POST: async ({ request }) => {
        const { handleSourceStatePost } = await import("@/lib/etl-source-state.server");
        return handleSourceStatePost(request);
      },
    },
  },
});
