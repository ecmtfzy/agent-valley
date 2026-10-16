import { expect, test } from '@playwright/test';

test.describe('reduced motion', () => {
  test.use({ reducedMotion: 'reduce' });
  test('nothing moves and the panel stays open', async ({ page }) => {
    await page.goto('/');
    await page.waitForTimeout(800);
    await expect(page.locator('.screen')).toHaveAttribute('data-state', 'open');
    expect(await page.evaluate(() => document.getAnimations().filter((a) => a.playState === 'running').length)).toBe(0);
  });
});

test('the panel opens once on load and stays open', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('.screen')).toHaveAttribute('data-opened', '', { timeout: 2000 });
  await expect(page.locator('.screen')).toHaveAttribute('data-state', 'open');
  await page.waitForTimeout(1500);
  await expect(page.locator('.screen')).toHaveAttribute('data-state', 'open');
});

test('the floating bits are hidden from screen readers', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('/');
  await expect(page.locator('.floating')).toHaveAttribute('aria-hidden', 'true');
  await expect(page.locator('.floating')).toBeVisible();
});

test('a picture comes up as it scrolls into view', async ({ page }) => {
  await page.goto('/');
  const terms = page.locator('.reveal:has(.terms)');
  // Past the layout's 3 s failsafe: with React here, the picture still waits.
  await page.waitForTimeout(3500);
  await expect(terms).not.toHaveClass(/shown/);
  expect(await terms.evaluate((el) => getComputedStyle(el).opacity)).toBe('0');
  await terms.scrollIntoViewIfNeeded();
  await expect(terms).toHaveClass(/shown/);
});

test('sections off the screen rest', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('/');
  await expect(page.locator('section.crew')).toHaveClass(/idle/);
  await expect(page.locator('section.hero')).not.toHaveClass(/idle/);
});

test('a waving face keeps its two frames in turn', async ({ page }) => {
  await page.goto('/');
  const delays = await page.locator('.wave').evaluateAll((all) =>
    all.map((w) => [...w.querySelectorAll('img')].map((img) => getComputedStyle(img).animationDelay)),
  );
  expect(delays.length).toBeGreaterThan(1);
  for (const [first, second] of delays) expect(first).toBe(second);
});

test('a page whose scripts never arrive still shows everything', async ({ page }) => {
  await page.route('**/_next/static/chunks/*.js', (route) => route.abort());
  await page.goto('/');
  await page.waitForTimeout(3500);
  expect(await page.locator('.panel').evaluate((el) => getComputedStyle(el).clipPath)).not.toContain('22.34%');
  for (const shown of await page.locator('.reveal').all()) {
    await shown.scrollIntoViewIfNeeded();
    expect(await shown.evaluate((el) => getComputedStyle(el).opacity)).toBe('1');
  }
});

test('a printed page shows every picture', async ({ page }) => {
  await page.goto('/');
  await page.waitForTimeout(600);
  await page.emulateMedia({ media: 'print' });
  for (const opacity of await page.locator('.reveal').evaluateAll((all) => all.map((el) => getComputedStyle(el).opacity))) {
    expect(opacity).toBe('1');
  }
});

test('Stop stops every animation', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'Stop the animations' }).click();
  await page.waitForTimeout(300);
  expect(await page.evaluate(() => document.getAnimations().filter((a) => a.playState === 'running').length)).toBe(0);
});

test('a picture still waiting shows at once when Stop is pressed', async ({ page }) => {
  await page.goto('/');
  await page.waitForTimeout(500);
  await page.getByRole('button', { name: 'Stop the animations' }).click();
  expect(await page.locator('.reveal:has(.terms)').evaluate((el) => getComputedStyle(el).opacity)).toBe('1');
});

test("only the hero's pictures load ahead", async ({ page }) => {
  await page.goto('/');
  const ahead = await page.evaluate(() => {
    const top = new Set([...document.querySelectorAll('header img, .hero img')].map((img) => (img as HTMLImageElement).src));
    return [...document.querySelectorAll('link[rel=preload][as=image]')].map((l) => (l as HTMLLinkElement).href).filter((href) => !top.has(href));
  });
  expect(ahead).toEqual([]);
});

test("the footer's lamps rest while it is off the screen", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('/');
  await expect(page.locator('footer')).toHaveClass(/idle/);
});
