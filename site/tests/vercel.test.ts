import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { expect, test } from 'vitest';
import { CSP } from '@/lib/csp';

// On Vercel the policy also goes out as a header, which the page's own tag cannot do: it covers
// what loads before the tag, and it may forbid framing.
test('vercel.json sends the page policy as a header, framing forbidden', () => {
  const config = JSON.parse(readFileSync(join(__dirname, '../vercel.json'), 'utf8'));
  const all = config.headers?.find((h: { source: string }) => h.source === '/(.*)');
  const sent = all?.headers.find((h: { key: string }) => h.key === 'Content-Security-Policy')?.value;
  expect(sent).toBe(`${CSP}; frame-ancestors 'none'`);
});
