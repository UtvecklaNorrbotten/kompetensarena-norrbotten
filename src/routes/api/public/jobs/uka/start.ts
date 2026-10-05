import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/public/jobs/uka/start")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { handleUkaStart } = await import("@/lib/uka-etl.server");
        return handleUkaStart(request);
      },
    },
  },
});

