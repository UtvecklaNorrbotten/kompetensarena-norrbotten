import { createFileRoute } from '@tanstack/react-router';
export const Route = createFileRoute('/api/public/jobs/company-data')({
  server: { handlers: {
    GET: async ({request}) => (await import('@/lib/company-data.server')).handleCompanyData(request),
    POST: async ({request}) => (await import('@/lib/company-data.server')).handleCompanyData(request),
  } },
});
