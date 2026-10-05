import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/public/jobs/uka/chunk")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { handleUkaChunk } = await import("@/lib/uka-etl.server");
        return handleUkaChunk(request);
      },
    },
  },
});
