import { expect, type Page, test } from '@playwright/test';

// The needs-you motion, played by the scroll over its track (lib/scrub.ts: frames 0 to 175 over nine screens).
const frame = (page: Page) => page.locator('.s-figure').getAttribute('data-frame').then(Number);
// Scrolls so the track is `at` of the way through: 0 its top at the top of the screen, 1 its foot at the foot.
const scrubTo = async (page: Page, at: number) => {
  await page.locator('.needs-you').evaluate((s, at) => {
    const track = s.querySelector<HTMLElement>('.s-track')!;
    const top = track.getBoundingClientRect().top + scrollY;
    scrollTo(0, top + at * (track.offsetHeight - innerHeight));
  }, at);
  await page.waitForTimeout(150);
};

test('the needs-you section shows the panel the app draws, with its still', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Know the moment one needs you.' })).toBeVisible();
  await expect(page.getByRole('img', { name: /^The bar beside the notch, while three agents work\./ })).toBeVisible();
  await page.locator('.s-still').scrollIntoViewIfNeeded();
  await expect.poll(() => page.locator('.s-still').evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth)).toBe(1500);
});

test.describe('as you scroll', () => {
  test.use({ viewport: { width: 1280, height: 800 } });

  test('the frame follows the scroll, both ways', async ({ page }) => {
    await page.goto('/');
    await page.locator('.needs-you[data-scrub]').waitFor();
    await scrubTo(page, 0);
    expect(await frame(page)).toBe(0);
    await scrubTo(page, 0.4);
    expect(await frame(page)).toBe(70);
    await scrubTo(page, 1);
    expect(await frame(page)).toBe(175);
    await scrubTo(page, 0.25);
    expect(await frame(page)).toBe(44);
  });

  test('the track is nine screens tall only while it plays', async ({ page }) => {
    await page.goto('/');
    await page.locator('.needs-you[data-scrub]').waitFor();
    expect(await page.locator('.s-track').evaluate((t: HTMLElement) => t.offsetHeight / innerHeight)).toBeCloseTo(9, 1);
  });

  test('Stop in the middle folds the track and keeps the reader at the section', async ({ page }) => {
    await page.goto('/');
    await page.locator('.needs-you[data-scrub]').waitFor();
    await scrubTo(page, 0.6);
    await page.getByRole('button', { name: 'Stop the animations' }).dispatchEvent('click');
    await expect(page.locator('.needs-you')).not.toHaveAttribute('data-scrub');
    expect(await page.locator('.s-track').evaluate((t: HTMLElement) => t.offsetHeight < innerHeight * 2)).toBe(true);
    await expect(page.locator('.s-still')).toBeInViewport();
  });

  test('Play after a remembered Stop brings the scrub back without a reload', async ({ page }) => {
    await page.addInitScript(() => localStorage.setItem('still', '1'));
    await page.goto('/');
    await page.locator('.needs-you').scrollIntoViewIfNeeded();
    await page.waitForTimeout(500);
    await expect(page.locator('.needs-you')).not.toHaveAttribute('data-scrub');
    await page.getByRole('button', { name: 'Play the animations' }).dispatchEvent('click');
    await page.locator('.needs-you[data-scrub]').waitFor();
  });

  test('a jump past the section, or a resize, keeps the frame in bounds', async ({ page }) => {
    await page.goto('/');
    await page.locator('.needs-you[data-scrub]').waitFor();
    // End and Home scroll smoothly: the frame is read once the page has come to rest.
    await page.keyboard.press('End');
    await expect.poll(() => frame(page)).toBe(175);
    await page.keyboard.press('Home');
    await expect.poll(() => frame(page)).toBe(0);
    await scrubTo(page, 0.5);
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(300);
    // The layout above moves on a resize, so the frame is checked against where the track is now.
    const expected = await page.locator('.s-track').evaluate((t: HTMLElement) => {
      const box = t.getBoundingClientRect();
      return Math.round(Math.min(1, Math.max(0, -box.top / (box.height - innerHeight))) * 175);
    });
    expect(await frame(page)).toBe(expected);
  });

  test('the player breaks no part of the page policy and asks nothing of other sites', async ({ page }) => {
    const outside: string[] = [];
    page.on('request', (r) => {
      if (!r.url().startsWith('http://127.0.0.1:4321')) outside.push(r.url());
    });
    await page.addInitScript(() =>
      document.addEventListener('securitypolicyviolation', (e) => {
        const w = window as unknown as { csp?: string[] };
        (w.csp ??= []).push(`${e.violatedDirective} ${e.blockedURI}`);
      }),
    );
    await page.goto('/');
    await page.locator('.needs-you[data-scrub]').waitFor();
    await scrubTo(page, 0);
    await page.locator('.s-player').waitFor();
    for (const at of [0, 0.3, 0.6, 1]) await scrubTo(page, at);
    expect(await page.evaluate(() => (window as unknown as { csp?: string[] }).csp ?? [])).toEqual([]);
    expect(outside).toEqual([]);
  });
});

test.describe('reduced motion', () => {
  test.use({ reducedMotion: 'reduce' });
  test('still only, normal height, no Remotion loaded', async ({ page }) => {
    const asked: string[] = [];
    page.on('request', (r) => asked.push(r.url()));
    await page.goto('/');
    await page.locator('.needs-you').scrollIntoViewIfNeeded();
    await page.waitForTimeout(800);
    await expect(page.locator('.needs-you')).not.toHaveAttribute('data-scrub');
    expect(await page.locator('.s-track').evaluate((t: HTMLElement) => t.offsetHeight < innerHeight * 2)).toBe(true);
    await expect(page.locator('.s-still')).toBeVisible();
    expect(await page.locator('.s-figure [inert]').count()).toBe(0);
    // The player's chunk is the only one that names the panel's pictures.
    const chunks = asked.filter((u) => u.includes('/_next/static/chunks/'));
    for (const url of chunks) expect(await (await page.request.get(url)).text()).not.toContain('open-allowed.webp');
  });
});

test('a short screen gets the still', async ({ page }) => {
  await page.setViewportSize({ width: 800, height: 400 });
  await page.goto('/');
  await page.locator('.needs-you').scrollIntoViewIfNeeded();
  await page.waitForTimeout(800);
  await expect(page.locator('.needs-you')).not.toHaveAttribute('data-scrub');
});

// A reader further down the page, at the terminal's heading, keeps their place when the track
// above folds or grows. The bar's button is pressed without Playwright's click, which scrolls the
// page to bring a sticky button into view and would move the reader itself.
const terminalTop = (page: Page) => page.locator('section.terminal h2').evaluate((h) => Math.round(h.getBoundingClientRect().top));
const toTerminal = (page: Page) => page.locator('section.terminal h2').evaluate((h) => scrollTo(0, h.getBoundingClientRect().top + scrollY - 200));

test.describe('a reader further down', () => {
  test.use({ viewport: { width: 1280, height: 800 } });

  test('Stop keeps their place', async ({ page }) => {
    await page.goto('/');
    await page.locator('.needs-you[data-scrub]').waitFor();
    await toTerminal(page);
    await page.waitForTimeout(200);
    const was = await terminalTop(page);
    await page.getByRole('button', { name: 'Stop the animations' }).dispatchEvent('click');
    await expect(page.locator('.needs-you')).not.toHaveAttribute('data-scrub');
    await page.waitForTimeout(200);
    expect(Math.abs((await terminalTop(page)) - was)).toBeLessThanOrEqual(2);
  });

  test('Play after a remembered Stop keeps their place, and the scrub plays', async ({ page }) => {
    await page.addInitScript(() => localStorage.setItem('still', '1'));
    await page.goto('/');
    await toTerminal(page);
    await page.waitForTimeout(200);
    const was = await terminalTop(page);
    await page.getByRole('button', { name: 'Play the animations' }).dispatchEvent('click');
    await page.locator('.needs-you[data-scrub]').waitFor();
    await page.waitForTimeout(200);
    expect(Math.abs((await terminalTop(page)) - was)).toBeLessThanOrEqual(2);
    await scrubTo(page, 0.4);
    expect(await frame(page)).toBe(70);
    await expect(page.locator('.s-player')).toBeVisible();
  });
});

test('turning a phone keeps a reader further down in place', async ({ page }) => {
  // The next section's heading: the text between it and the track is the least that wraps anew.
  const costsTop = () => page.locator('section.costs h2').evaluate((h) => Math.round(h.getBoundingClientRect().top));
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  await page.locator('.needs-you[data-scrub]').waitFor();
  await page.locator('section.costs h2').evaluate((h) => scrollTo(0, h.getBoundingClientRect().top + scrollY - 200));
  await page.waitForTimeout(200);
  // The text above wraps anew at each width, so the reader drifts a little, as on any page; the
  // heading stays on the screen rather than thousands of pixels away.
  for (const [width, height] of [[844, 390], [390, 844]]) {
    await page.setViewportSize({ width, height });
    await page.waitForTimeout(400);
    expect(Math.abs(await costsTop())).toBeLessThan(height);
  }
});

test('a player that never arrives leaves the still at its normal height', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.route('**/_next/static/chunks/*.js', async (route) => {
    const response = await route.fetch();
    // Only the motion's own chunk names its pictures.
    if ((await response.text()).includes('open-allowed.webp')) return route.abort();
    return route.fulfill({ response });
  });
  await page.goto('/');
  await page.locator('.needs-you').scrollIntoViewIfNeeded();
  await page.waitForTimeout(1500);
  await expect(page.locator('.needs-you')).not.toHaveAttribute('data-scrub');
  expect(await page.locator('.s-track').evaluate((t: HTMLElement) => t.offsetHeight < innerHeight * 2)).toBe(true);
});

test('the pictures are drawn before the player covers the still', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.route('**/needs-you/*.webp', async (route) => {
    if (!route.request().url().endsWith('still.webp')) await new Promise((r) => setTimeout(r, 1500));
    return route.continue();
  });
  await page.goto('/');
  await page.locator('.needs-you').scrollIntoViewIfNeeded();
  await page.locator('.s-player').waitFor();
  await scrubTo(page, 0.5);
  for (const img of await page.locator('.s-player img').all()) {
    expect(await img.evaluate((i: HTMLImageElement) => i.complete && i.naturalWidth > 0)).toBe(true);
  }
});

// Side by side on a screen tall enough for it, the copy is held beside the picture; otherwise
// the picture alone is held and the copy scrolls by.
for (const [width, height, copyHeld] of [
  [1280, 800, true],
  [1024, 640, true],
  [1440, 560, false],
  [900, 560, false],
  [899, 700, false],
  [768, 600, false],
  [390, 844, false],
] as const) {
  test(`what is held fits the screen at ${width}×${height}`, async ({ page }) => {
    await page.setViewportSize({ width, height });
    await page.goto('/');
    await page.locator('.needs-you[data-scrub]').waitFor();
    await scrubTo(page, 0.5);
    expect(await page.locator('.s-copy').evaluate((c) => getComputedStyle(c).position)).toBe(copyHeld ? 'sticky' : 'static');
    const box = (selector: string) => page.locator(selector).evaluate((e) => e.getBoundingClientRect().toJSON() as DOMRect);
    for (const selector of copyHeld ? ['.s-copy h2', '.s-copy li:last-child', '.s-figure'] : ['.s-figure']) {
      const { top, bottom } = await box(selector);
      expect(top, selector).toBeGreaterThanOrEqual(64);
      expect(bottom, selector).toBeLessThanOrEqual(height);
    }
  });
}

// A reader who has made the browser's text larger: the copy is held only while it fits, and never
// runs into the next section.
for (const size of [20, 24, 32]) {
  test(`text at ${size}px stays whole and in its section`, async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    const cdp = await page.context().newCDPSession(page);
    await cdp.send('Page.setFontSizes', { fontSizes: { standard: size } });
    await page.goto('/');
    await page.locator('.needs-you[data-scrub]').waitFor();
    for (const at of [0.2, 0.5, 1]) {
      await scrubTo(page, at);
      const { held, h2, last, section } = await page.locator('.needs-you').evaluate((s) => ({
        held: getComputedStyle(s.querySelector('.s-copy')!).position === 'sticky',
        h2: s.querySelector('.s-copy h2')!.getBoundingClientRect().top,
        last: s.querySelector('.s-copy li:last-child')!.getBoundingClientRect().bottom,
        section: s.getBoundingClientRect().bottom,
      }));
      expect(last).toBeLessThanOrEqual(section);
      if (held) {
        expect(h2).toBeGreaterThanOrEqual(64);
        expect(last).toBeLessThanOrEqual(800);
      }
    }
  });
}
