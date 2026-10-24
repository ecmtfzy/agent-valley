import { expect, test } from '@playwright/test';

test.describe('reduced motion', () => {
  test.use({ reducedMotion: 'reduce' });
  test('nothing moves and the panel stands open', async ({ page }) => {
    await page.goto('/');
    await page.waitForTimeout(800);
    await expect(page.locator('.screen')).toHaveAttribute('data-state', 'open');
    expect(await page.evaluate(() => document.getAnimations().filter((a) => a.playState === 'running').length)).toBe(0);
  });
  test('before the scripts arrive the panel is drawn open already', async ({ page }) => {
    await page.route((url) => url.pathname.endsWith('.js'), (route) => route.abort());
    await page.goto('/');
    expect(await page.locator('.screen .panel').evaluate((el) => getComputedStyle(el).clipPath)).not.toContain('22.34%');
  });
});

test('the panel stands open from the start, and nothing shuts it on its own', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('.screen')).toHaveAttribute('data-ready', '');
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
  const terms = page.locator('.reveal:has(.anatomy)');
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

test('scripts that come after the page gave up on them leave the panel open', async ({ page }) => {
  await page.route((url) => url.pathname.endsWith('.js'), async (route) => {
    await new Promise((done) => setTimeout(done, 3500));
    await route.continue();
  });
  await page.goto('/');
  await expect(page.locator('.screen')).toHaveAttribute('data-ready', '', { timeout: 15000 });
  await page.waitForTimeout(500);
  await expect(page.locator('.screen')).toHaveAttribute('data-state', 'open');
});

test('a page whose scripts never arrive still shows everything', async ({ page }) => {
  await page.route('**/_next/static/chunks/*.js', (route) => route.abort());
  await page.goto('/');
  await page.waitForTimeout(3500);
  expect(await page.locator('.panel').evaluate((el) => getComputedStyle(el).clipPath)).not.toContain('22.34%');
  expect(await page.locator('.term').evaluateAll((all) => all.map((t) => getComputedStyle(t).opacity))).toEqual(['1', '1', '1', '1', '1']);
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

// Off the screen a section's loops already rest (.idle), so each part is brought into view: there
// only Stop can be what holds them.
test('Stop stops every animation, all the way down the page', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('/');
  await page.waitForTimeout(1500);
  const running = () =>
    page.evaluate(() =>
      document.getAnimations().filter((a) => a.playState === 'running').map((a) => ('animationName' in a ? a.animationName : (a as CSSTransition).transitionProperty)),
    );
  expect((await running()).length).toBeGreaterThan(0);
  await page.getByRole('button', { name: 'Stop the animations' }).click();
  for (const part of await page.locator('.hero, .section, .credits, .foot').all()) {
    await part.scrollIntoViewIfNeeded();
    await page.waitForTimeout(300);
    expect(await running(), (await part.getAttribute('class')) ?? '').toEqual([]);
  }
});

test('a picture still waiting shows at once when Stop is pressed', async ({ page }) => {
  await page.goto('/');
  await page.waitForTimeout(500);
  await page.getByRole('button', { name: 'Stop the animations' }).click();
  expect(await page.locator('.reveal:has(.anatomy)').evaluate((el) => getComputedStyle(el).opacity)).toBe('1');
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
