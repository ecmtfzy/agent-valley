import { expect, type Page, test } from '@playwright/test';

// "Five agents running.": as the page scrolls, the five terminals pop up one by one onto a pile,
// the one waiting for an answer first, buried by the rest. On a wide screen the section holds
// still meanwhile, as Apple's pages do.

// Scrolls so that the top of `selector` sits at `share` of the screen's height.
const place = async (page: Page, selector: string, share: number) => {
  await page.evaluate(
    ([sel, s]) => {
      const el = document.querySelector(sel as string)!;
      scrollTo({ top: scrollY + el.getBoundingClientRect().top - innerHeight * (s as number), behavior: 'instant' });
    },
    [selector, share],
  );
  await page.waitForTimeout(120);
};
const count = async (page: Page) => Number(await page.locator('.terms').getAttribute('data-n'));
const opacities = (page: Page) => page.locator('.term').evaluateAll((all) => all.map((t) => getComputedStyle(t).opacity));

test.describe('on a wide screen', () => {
  test.use({ viewport: { width: 1280, height: 800 }, reducedMotion: 'no-preference' });

  test('the section holds still while the five terminals pop up one by one', async ({ page }) => {
    await page.goto('/');
    const section = page.locator('section.problem');
    expect((await section.boundingBox())!.height).toBeGreaterThan(800 * 2);
    // Past the layout's 3 s failsafe: with React here, the pile still waits for the reader.
    await page.waitForTimeout(3500);
    expect(await opacities(page)).toEqual(['0', '0', '0', '0', '0']);
    await place(page, 'section.problem', 1);
    expect(await count(page)).toBe(0);
    await place(page, 'section.problem', 0.25);
    expect(await count(page)).toBe(1);
    // Down through the section a tenth of a screen at a time.
    const seen: { n: number; top: number }[] = [];
    for (let step = 0; step < 20; step++) {
      await page.mouse.wheel(0, 80);
      await page.waitForTimeout(80);
      seen.push({ n: await count(page), top: Math.round((await page.locator('.problem-stage').boundingBox())!.y) });
    }
    const ns = seen.map((s) => s.n);
    expect(ns).toEqual([...ns].sort((a, b) => a - b));
    for (const n of [2, 3, 4, 5]) expect(ns).toContain(n);
    // Held under the top bar as the third, fourth and fifth come up, and a while with all five up;
    // then let go.
    const held = (top: number) => Math.abs(top - 64) <= 2;
    for (const n of [3, 4, 5]) expect(held(seen.find((s) => s.n === n)!.top), `n=${n}`).toBe(true);
    expect(seen.filter((s) => s.n === 5 && held(s.top)).length).toBeGreaterThan(1);
    expect(seen.at(-1)!.top).toBeLessThan(60);
  });

  test('the stage fills the section, held from its top right to its end', async ({ page }) => {
    await page.goto('/');
    const top = (selector: string) => page.locator(selector).evaluate((el) => Math.round(el.getBoundingClientRect().top));
    await place(page, 'section.problem', 0.4);
    expect((await top('.problem-stage')) - (await top('section.problem'))).toBeLessThanOrEqual(1);
    // The section's end just below the foot of the screen: the stage is still held.
    await page.evaluate(() => {
      const section = document.querySelector('section.problem')!;
      scrollTo({ top: scrollY + section.getBoundingClientRect().bottom - innerHeight - 2, behavior: 'instant' });
    });
    await page.waitForTimeout(100);
    expect(await top('.problem-stage')).toBe(64);
  });

  test('each terminal springs in and the ones not yet called stay hidden', async ({ page }) => {
    await page.goto('/');
    await place(page, 'section.problem', 0.25);
    await page.mouse.wheel(0, 0.75 * 800);
    await page.waitForTimeout(900);
    const n = await count(page);
    expect(n).toBeGreaterThan(1);
    expect(n).toBeLessThan(5);
    const seen = await opacities(page);
    expect(seen.slice(0, n)).toEqual(Array(n).fill('1'));
    expect(seen.slice(n)).toEqual(Array(5 - n).fill('0'));
    expect(await page.locator('.term').first().evaluate((t) => getComputedStyle(t).transitionTimingFunction)).toContain('cubic-bezier(0.34, 1.56');
  });

  test('scrolling back up takes them off again', async ({ page }) => {
    await page.goto('/');
    await place(page, 'section.problem', -1.2);
    expect(await count(page)).toBe(5);
    await place(page, 'section.problem', 0.25);
    expect(await count(page)).toBe(1);
  });

  test('Stop shows the whole pile at once, and the page does not jump under the reader', async ({ page }) => {
    await page.goto('/');
    const length = async () => (await page.locator('section.problem').boundingBox())!.height;
    const before = await length();
    await page.getByRole('button', { name: 'Stop the animations' }).click();
    // Chrome holds the reader's place when the page above changes length; Safari does not.
    expect(await length()).toBe(before);
    await place(page, '.terms', 0.95);
    expect(await opacities(page)).toEqual(['1', '1', '1', '1', '1']);
  });
});

test.describe('on a phone', () => {
  test.use({ viewport: { width: 390, height: 844 }, reducedMotion: 'no-preference' });

  test('the terminals pop up as the picture rises, with nothing held', async ({ page }) => {
    await page.goto('/');
    expect((await page.locator('section.problem').boundingBox())!.height).toBeLessThan(844 * 1.5);
    await place(page, '.terms', 0.95);
    expect(await count(page)).toBe(0);
    await place(page, '.terms', 0.75);
    const n = await count(page);
    expect(n).toBeGreaterThan(0);
    expect(n).toBeLessThan(5);
    await place(page, '.terms', 0.45);
    expect(await count(page)).toBe(5);
  });
});

test.describe('with motion reduced', () => {
  test.use({ viewport: { width: 1280, height: 800 }, reducedMotion: 'reduce' });

  test('the pile stands whole and the section holds nothing', async ({ page }) => {
    await page.goto('/');
    expect((await page.locator('section.problem').boundingBox())!.height).toBeLessThan(800 * 1.5);
    await place(page, '.terms', 0.95);
    expect(await opacities(page)).toEqual(['1', '1', '1', '1', '1']);
  });
});
