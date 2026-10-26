import { expect, type Page, test } from '@playwright/test';

// The needs-you motion plays on its own, round and round, over its still.
const looks = (page: Page) => page.locator('.s-figure').screenshot();
// The largest step of any colour of any pixel between two pictures, read by the page itself.
const apart = (page: Page, a: Buffer, b: Buffer) =>
  page.evaluate(async (both) => {
    const pixels = async (png: string) => {
      const picture = await createImageBitmap(new Blob([Uint8Array.from(atob(png), (c) => c.charCodeAt(0))]));
      const pen = new OffscreenCanvas(picture.width, picture.height).getContext('2d')!;
      pen.drawImage(picture, 0, 0);
      return pen.getImageData(0, 0, picture.width, picture.height).data;
    };
    const [x, y] = await Promise.all(both.map(pixels));
    if (x.length !== y.length) return Infinity;
    let most = 0;
    for (let i = 0; i < x.length; i++) most = Math.max(most, Math.abs(x[i] - y[i]));
    return most;
  }, [a.toString('base64'), b.toString('base64')]);
// Whether the figure changes within 2.4 s, longer than the motion ever rests between beats.
// Chrome paints a still picture a shade off now and then, never more than a step or two.
const moves = async (page: Page) => {
  const first = await looks(page);
  for (let i = 0; i < 6; i++) {
    await page.waitForTimeout(400);
    if ((await apart(page, first, await looks(page))) > 8) return true;
  }
  return false;
};
const reach = async (page: Page) => {
  await page.goto('/');
  await page.locator('.needs-you').scrollIntoViewIfNeeded();
};

test('the needs-you section shows the panel the app draws, with its still', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Know the moment one needs you.' })).toBeVisible();
  await expect(page.getByRole('img', { name: /^The top of a Mac screen\. An agent works in a terminal/ })).toBeVisible();
  await page.locator('.s-still').scrollIntoViewIfNeeded();
  await expect.poll(() => page.locator('.s-still').evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth)).toBe(1500);
});

test.describe('where the page may move', () => {
  test.use({ viewport: { width: 1280, height: 800 }, reducedMotion: 'no-preference' });

  test('the motion plays on its own, and the section is as tall as its content', async ({ page }) => {
    await reach(page);
    await page.locator('.s-player').waitFor();
    expect(await page.locator('section.needs-you').evaluate((s: HTMLElement) => s.offsetHeight / innerHeight)).toBeLessThan(1.5);
    expect(await moves(page)).toBe(true);
  });

  test('it starts again once it ends', async ({ page }) => {
    await reach(page);
    await page.locator('.s-player').waitFor();
    // Past the end of one round (8 s): a motion that stopped there would hold its last frame.
    await page.waitForTimeout(8500);
    expect(await moves(page)).toBe(true);
  });

  test('Stop shows the still, and Play brings the motion back', async ({ page }) => {
    await reach(page);
    await page.locator('.s-player').waitFor();
    await page.getByRole('button', { name: 'Stop the animations' }).dispatchEvent('click');
    await expect(page.locator('.s-player')).toHaveCount(0);
    await expect(page.locator('.s-still')).toBeVisible();
    expect(await moves(page)).toBe(false);
    await page.getByRole('button', { name: 'Play the animations' }).dispatchEvent('click');
    await page.locator('.s-player').waitFor();
    expect(await moves(page)).toBe(true);
  });

  test('Play after a remembered Stop starts the motion without a reload', async ({ page }) => {
    await page.addInitScript(() => localStorage.setItem('still', '1'));
    await reach(page);
    await page.waitForTimeout(800);
    await expect(page.locator('.s-player')).toHaveCount(0);
    await page.getByRole('button', { name: 'Play the animations' }).dispatchEvent('click');
    await page.locator('.s-player').waitFor();
  });

  test('the player breaks no part of the page policy and asks nothing of other sites', async ({ page }) => {
    const outside: string[] = [];
    page.on('request', (r) => {
      if (!r.url().startsWith('http://127.0.0.1:4321') && !r.url().startsWith('https://api.producthunt.com/widgets/')) outside.push(r.url());
    });
    await page.addInitScript(() =>
      document.addEventListener('securitypolicyviolation', (e) => {
        const w = window as unknown as { csp?: string[] };
        (w.csp ??= []).push(`${e.violatedDirective} ${e.blockedURI}`);
      }),
    );
    await reach(page);
    await page.locator('.s-player').waitFor();
    await page.waitForTimeout(2000);
    expect(await page.evaluate(() => (window as unknown as { csp?: string[] }).csp ?? [])).toEqual([]);
    expect(outside).toEqual([]);
  });

  test('a short screen plays it too', async ({ page }) => {
    await page.setViewportSize({ width: 800, height: 400 });
    await reach(page);
    await page.locator('.s-player').waitFor();
    expect(await moves(page)).toBe(true);
  });

  test('a player that never arrives leaves the still', async ({ page }) => {
    await page.route('**/_next/static/chunks/*.js', async (route) => {
      const response = await route.fetch();
      // Only the motion's own chunk names its pictures.
      if ((await response.text()).includes('open-allowed.webp')) return route.abort();
      return route.fulfill({ response });
    });
    await reach(page);
    await page.waitForTimeout(1500);
    await expect(page.locator('.s-player')).toHaveCount(0);
    await expect(page.locator('.s-still')).toBeVisible();
  });

  test('the pictures are drawn before the player covers the still', async ({ page }) => {
    await page.route('**/needs-you/*.webp', async (route) => {
      if (!route.request().url().endsWith('still.webp')) await new Promise((r) => setTimeout(r, 1500));
      return route.continue();
    });
    await reach(page);
    await page.locator('.s-player').waitFor();
    for (const img of await page.locator('.s-player img').all()) {
      expect(await img.evaluate((i: HTMLImageElement) => i.complete && i.naturalWidth > 0)).toBe(true);
    }
  });
});

test.describe('reduced motion', () => {
  test.use({ reducedMotion: 'reduce' });
  test('still only, no Remotion loaded', async ({ page }) => {
    const asked: string[] = [];
    page.on('request', (r) => asked.push(r.url()));
    await reach(page);
    await page.waitForTimeout(800);
    await expect(page.locator('.s-still')).toBeVisible();
    await expect(page.locator('.s-player')).toHaveCount(0);
    // The player's chunk is the only one that names the panel's pictures.
    const chunks = asked.filter((u) => u.includes('/_next/static/chunks/'));
    for (const url of chunks) expect(await (await page.request.get(url)).text()).not.toContain('open-allowed.webp');
  });
});
