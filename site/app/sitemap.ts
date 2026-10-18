import type { MetadataRoute } from 'next';

export const dynamic = 'force-static';

export default function sitemap(): MetadataRoute.Sitemap {
  return [{ url: 'https://agentvalley.app/' }, { url: 'https://agentvalley.app/comics/lunch-break/' }];
}
