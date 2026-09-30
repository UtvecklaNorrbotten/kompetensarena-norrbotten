import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/api/public/jobs/af-revisions")({
  server: {
    handlers: {
      GET: async ({ request }) => {
        const { handleAfRevisions } = await import("@/lib/af-revisions.server");
        return handleAfRevisions(request);
      },
      POST: async ({ request }) => {
        const { handleAfRevisions } = await import("@/lib/af-revisions.server");
        return handleAfRevisions(request);
      },
    },
  },
});
