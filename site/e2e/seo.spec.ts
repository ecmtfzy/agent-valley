import { expect, test } from '@playwright/test';

// The head the old page gave search engines and link previews, kept word for word.
const TITLE = 'AgentValley — Every Claude Code agent in your notch';
const DESCRIPTION =
  'A free, open-source Mac app that shows every Claude Code agent, sub-agents too, in your notch. See who is working, on which model, and who needs you.';
const CSP =
  "default-src 'self'; img-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; base-uri 'none'; form-action 'none'";

test('the head carries the old title, description, canonical, preview image and policy', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveTitle(TITLE);
  await expect(page.locator('meta[name="description"]')).toHaveAttribute('content', DESCRIPTION);
  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', 'https://agentvalley.app/');
  await expect(page.locator('meta[property="og:image"]')).toHaveAttribute('content', 'https://agentvalley.app/og.png');
  await expect(page.locator('meta[property="og:url"]')).toHaveAttribute('content', 'https://agentvalley.app/');
  await expect(page.locator('meta[name="twitter:card"]')).toHaveAttribute('content', 'summary_large_image');
  await expect(page.locator('meta[http-equiv="Content-Security-Policy"]')).toHaveAttribute('content', CSP);
  await expect(page.locator('link[rel="apple-touch-icon"]')).toHaveAttribute('href', '/apple-touch-icon.png');
});

test('the structured data describes the app as software', async ({ page }) => {
  await page.goto('/');
  const ld = JSON.parse(await page.locator('script[type="application/ld+json"]').textContent() ?? '{}');
  expect(ld['@type']).toBe('SoftwareApplication');
  expect(ld.name).toBe('AgentValley');
  expect(ld.operatingSystem).toBe('macOS 15 or later');
  expect(ld.offers).toEqual({ '@type': 'Offer', price: '0', priceCurrency: 'USD' });
  expect(ld.sameAs).toEqual(['https://github.com/morsechimwai/agent-valley']);
});

test('robots.txt points at the sitemap, and the sitemap lists the page', async ({ request }) => {
  expect(await (await request.get('/robots.txt')).text()).toContain('Sitemap: https://agentvalley.app/sitemap.xml');
  expect(await (await request.get('/sitemap.xml')).text()).toContain('<loc>https://agentvalley.app/</loc>');
});

test('nothing is fetched from another site', async ({ page, baseURL }) => {
  const elsewhere: string[] = [];
  page.on('request', (r) => {
    if (!r.url().startsWith(baseURL!)) elsewhere.push(r.url());
  });
  await page.goto('/', { waitUntil: 'networkidle' });
  expect(elsewhere).toEqual([]);
});
