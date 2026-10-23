import { STRIPS } from '../app/comics/strips';
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

test('the structured data names the site and describes the app as software', async ({ page }) => {
  await page.goto('/');
  const all = (await page.locator('script[type="application/ld+json"]').allTextContents()).map((t) => JSON.parse(t));
  expect(all.find((d) => d['@type'] === 'WebSite')).toMatchObject({ name: 'AgentValley', url: 'https://agentvalley.app/' });
  const ld = all.find((d) => d['@type'] === 'SoftwareApplication');
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

for (const strip of STRIPS) {
  test(`the ${strip.title} page has its own head, its place in the site, and is in the sitemap`, async ({ page, request }) => {
    const url = `https://agentvalley.app/comics/${strip.slug}/`;
    await page.goto(`/comics/${strip.slug}/`);
    await expect(page).toHaveTitle(strip.headline);
    await expect(page.locator('meta[name="description"]')).toHaveAttribute('content', strip.description);
    await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', url);
    await expect(page.locator('meta[property="og:image"]')).toHaveAttribute('content', `https://agentvalley.app/comics/${strip.slug}-og.jpg`);
    await expect(page.locator('h1')).toHaveText(strip.title);
    const byline = page.locator('h1 + p');
    await expect(byline).toContainText('By morsechimwai');
    await expect(byline.locator('time')).toHaveAttribute('datetime', strip.date);
    const graphs = await page.locator('script[type="application/ld+json"]').allTextContents();
    const types = graphs.flatMap((g) => (JSON.parse(g)['@graph'] ?? []).map((n: { '@type': string }) => n['@type']));
    expect(types).toEqual(expect.arrayContaining(['Article', 'BreadcrumbList']));
    expect((await request.get(`/comics/${strip.slug}-og.jpg`)).ok()).toBe(true);
    expect(await (await request.get('/sitemap.xml')).text()).toContain(`<loc>${url}</loc>`);
  });
}

test('the funnies page lists every strip, newest first under its day, links each story, and is in the sitemap', async ({ page, request }) => {
  const url = 'https://agentvalley.app/comics/';
  await page.goto('/comics/');
  await expect(page).toHaveTitle('The Valley Funnies: comics about Claude Code');
  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', url);
  await expect(page.locator('h1')).toHaveText('The Valley Funnies');
  await expect(page.locator('main h3')).toHaveText(STRIPS.map((s) => s.title).reverse());
  await expect(page.locator('.f-dateline time')).toHaveText([...new Set(STRIPS.map((s) => s.date))].reverse().map((d) => new Date(`${d}T00:00:00Z`).toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric', timeZone: 'UTC' })));
  for (const s of STRIPS) await expect(page.locator(`main a[href="/comics/${s.slug}/"]`)).toHaveCount(1);
  await expect(page.locator('.f-byline')).toHaveText(STRIPS.map(() => 'By morsechimwai'));
  expect(await (await request.get('/sitemap.xml')).text()).toContain(`<loc>${url}</loc>`);
});

test('the newest day’s strips wear the NEW stamp, and no other strip does', async ({ page }) => {
  await page.goto('/comics/');
  const newest = STRIPS.map((s) => s.date).sort().at(-1);
  const fresh = STRIPS.filter((s) => s.date === newest).map((s) => s.title).reverse();
  await expect(page.locator('.f-card:has(.f-new) h3')).toHaveText(fresh);
});

test('clicking a strip picture opens its story, even while it lifts', async ({ page }) => {
  for (const s of [STRIPS[0], STRIPS[STRIPS.length - 1]]) {
    await page.goto('/comics/');
    const img = page.locator(`#${s.slug} ~ img`);
    await img.scrollIntoViewIfNeeded();
    await expect(img).toBeVisible();
    const box = (await img.boundingBox())!;
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.waitForTimeout(600);
    await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
    await expect(page).toHaveURL(new RegExp(`/comics/${s.slug}/$`));
  }
});

test('every page reaches the funnies from its foot', async ({ page }) => {
  for (const path of ['/', ...STRIPS.map((s) => `/comics/${s.slug}/`)]) {
    await page.goto(path);
    await expect(page.locator('footer a[href="/comics/"]')).toHaveCount(1);
  }
});

test('the funnies have an RSS feed, newest first, that every page names', async ({ page, request }) => {
  const feed = await (await request.get('/comics/feed.xml')).text();
  const links = [...feed.matchAll(/<link>([^<]+)<\/link>/g)].map((m) => m[1]).slice(1);
  expect(links).toEqual([...STRIPS].reverse().map((s) => `https://agentvalley.app/comics/${s.slug}/`));
  for (const path of ['/', '/comics/', `/comics/${STRIPS[0].slug}/`]) {
    await page.goto(path);
    await expect(page.locator('link[rel="alternate"][type="application/rss+xml"]')).toHaveAttribute('href', 'https://agentvalley.app/comics/feed.xml');
  }
});

test('search engines may show large pictures, and the sitemap names each strip picture', async ({ page, request }) => {
  await page.goto('/');
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute('content', /max-image-preview:large/);
  const map = await (await request.get('/sitemap.xml')).text();
  for (const s of STRIPS) expect(map).toContain(`<image:loc>https://agentvalley.app/comics/${s.slug}.webp</image:loc>`);
});

test('llms.txt sums up the site and lists every strip', async ({ request }) => {
  const text = await (await request.get('/llms.txt')).text();
  expect(text.startsWith('# AgentValley')).toBe(true);
  for (const s of STRIPS) expect(text).toContain(`https://agentvalley.app/comics/${s.slug}/`);
});

test('the funnies share their own front page, and IndexNow can find its key', async ({ page, request }) => {
  await page.goto('/comics/');
  await expect(page.locator('meta[property="og:image"]')).toHaveAttribute('content', 'https://agentvalley.app/comics/funnies-og.jpg');
  expect((await request.get('/comics/funnies-og.jpg')).ok()).toBe(true);
  expect(await (await request.get('/indexnow.txt')).text()).toMatch(/^[0-9a-f]{32}$/);
});
