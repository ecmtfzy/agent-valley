import type { MetadataRoute } from 'next';
import { STRIPS } from './comics/strips';

export const dynamic = 'force-static';

// The home page, the funnies, and a page per strip, each with the day it last changed.
export default function sitemap(): MetadataRoute.Sitemap {
  const newest = STRIPS.map((s) => s.date).sort().at(-1);
  return [
    { url: 'https://agentvalley.app/' },
    { url: 'https://agentvalley.app/comics/', lastModified: newest },
    ...STRIPS.map((s) => ({ url: `https://agentvalley.app/comics/${s.slug}/`, lastModified: s.date })),
  ];
}
