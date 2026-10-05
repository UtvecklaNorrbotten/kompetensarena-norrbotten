import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/public/jobs/uka/abort")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { handleUkaAbort } = await import("@/lib/uka-etl.server");
        return handleUkaAbort(request);
      },
    },
  },
});
