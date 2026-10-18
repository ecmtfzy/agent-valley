import { statSync } from 'node:fs';
import { join } from 'node:path';
import { STRIPS } from '../strips';

export const dynamic = 'force-static';

// The funnies as an RSS feed, newest strip first, each with its picture, for feed readers.
const SITE = 'https://agentvalley.app';
const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const day = (d: string) => new Date(`${d}T00:00:00Z`).toUTCString();

export function GET() {
  const items = STRIPS.map((s, i) => {
    const url = `${SITE}/comics/${s.slug}/`;
    const pic = `${s.slug}-1024.webp`;
    const bytes = statSync(join(process.cwd(), 'public/comics', pic)).size;
    return `<item>
<title>No. ${i + 1}: ${esc(s.title)}</title>
<link>${url}</link>
<guid isPermaLink="true">${url}</guid>
<pubDate>${day(s.date)}</pubDate>
<description>${esc(`${s.deck} ${s.inside}`)}</description>
<enclosure url="${SITE}/comics/${pic}" length="${bytes}" type="image/webp"/>
</item>`;
  }).reverse();
  const newest = STRIPS.map((s) => s.date).sort().at(-1)!;
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
<channel>
<title>The Valley Funnies</title>
<link>${SITE}/comics/</link>
<atom:link href="${SITE}/comics/feed.xml" rel="self" type="application/rss+xml"/>
<description>Four-panel pixel comics about working with Claude Code, drawn with the AgentValley crew.</description>
<language>en</language>
<lastBuildDate>${day(newest)}</lastBuildDate>
${items.join('\n')}
</channel>
</rss>
`;
  return new Response(xml, { headers: { 'Content-Type': 'application/rss+xml; charset=utf-8' } });
}
