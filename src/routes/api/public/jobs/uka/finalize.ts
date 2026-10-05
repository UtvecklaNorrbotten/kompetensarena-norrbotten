import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/public/jobs/uka/finalize")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { handleUkaFinalize } = await import("@/lib/uka-etl.server");
        return handleUkaFinalize(request);
      },
    },
  },
});
