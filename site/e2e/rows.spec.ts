import { expect, type Page, test } from '@playwright/test';

// The enlarged row in "Every agent gets a row.": each part is marked by a hand-drawn arrow whose
// label sits on the page outside the black box.
const PARTS = [
  { part: 'task', side: 'top' },
  { part: 'time · model', side: 'top' },
  { part: 'latest step · steps so far', side: 'bottom' },
  { part: 'type', side: 'bottom' },
] as const;

// Where an arrow's line ends, on the page.
const tip = (page: Page, part: string) =>
  page.locator(`.note[data-for="${part}"] path.line`).evaluate((line: SVGPathElement) => {
    const end = line.getPointAtLength(line.getTotalLength());
    const at = new DOMPoint(end.x, end.y).matrixTransform(line.getScreenCTM()!);
    return { x: at.x, y: at.y };
  });

for (const width of [1440, 1280, 1100, 1000, 900, 768, 640, 560]) {
  test(`at ${width}px each part has an arrow from a label outside the box`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    await page.goto('/');
    await page.locator('.anatomy').scrollIntoViewIfNeeded();
    await page.locator('.reveal.shown .anatomy').waitFor();
    await page.waitForTimeout(700);
    const box = (await page.locator('.anatomy').boundingBox())!;
    const fig = (await page.locator('figure.notes').boundingBox())!;
    // Each line of the row stays one line: the pens are drawn to its two edges.
    for (const line of await page.locator('.anatomy .p-line').all()) {
      const tops = await line.locator(':scope > [data-part]').evaluateAll((parts) => parts.map((el) => Math.round(el.getBoundingClientRect().top)));
      expect(new Set(tops).size).toBe(1);
    }
    for (const { part, side } of PARTS) {
      const note = page.locator(`.note[data-for="${part}"]`);
      await expect(note).toBeVisible();
      const label = (await note.locator('.note-label').boundingBox())!;
      expect(await note.locator('.note-label').textContent()).toBe(part);
      if (side === 'top') expect(label.y + label.height).toBeLessThanOrEqual(box.y);
      else expect(label.y).toBeGreaterThanOrEqual(box.y + box.height);
      // Inside the picture, clear of what is above and below it.
      expect(label.y).toBeGreaterThanOrEqual(fig.y);
      expect(label.y + label.height).toBeLessThanOrEqual(fig.y + fig.height);
      const target = (await page.locator(`.anatomy [data-part="${part}"]`).boundingBox())!;
      const end = await tip(page, part);
      expect(end.x).toBeGreaterThanOrEqual(target.x);
      expect(end.x).toBeLessThanOrEqual(target.x + target.width);
      const edge = side === 'top' ? target.y : target.y + target.height;
      expect(Math.abs(end.y - edge)).toBeLessThan(6);
    }
  });
}

test('a phone keeps the labels inside the box, over each part, and draws no arrows', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 800 });
  await page.goto('/');
  await page.locator('.anatomy').scrollIntoViewIfNeeded();
  for (const { part } of PARTS) await expect(page.locator(`.note[data-for="${part}"]`)).toBeHidden();
  const before = await page.locator('.anatomy [data-part="task"]').evaluate((el) => getComputedStyle(el, '::before').content);
  expect(before).toBe('"task"');
});

test.describe('reduced motion', () => {
  test.use({ reducedMotion: 'reduce', viewport: { width: 1280, height: 800 } });
  test('the arrows stand drawn from the start', async ({ page }) => {
    await page.goto('/');
    await page.locator('.anatomy').scrollIntoViewIfNeeded();
    for (const offset of await page.locator('.note path').evaluateAll((all) => all.map((p) => getComputedStyle(p).strokeDashoffset))) {
      expect(parseFloat(offset)).toBe(0);
    }
  });
});

test('the arrows draw in as the row comes into view, even well after the page loaded', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  await page.goto('/');
  // Past the 3 s after which a page without React gives up its waiting pictures.
  await page.waitForTimeout(3500);
  const offsets = () => page.locator('.note path').evaluateAll((all) => all.map((p) => parseFloat(getComputedStyle(p).strokeDashoffset)));
  for (const offset of await offsets()) expect(offset).toBeGreaterThan(1);
  await page.locator('.anatomy').scrollIntoViewIfNeeded();
  await expect.poll(async () => Math.max(...(await offsets())), { timeout: 4000 }).toBe(0);
});

// The row's time runs, as the app's does, while the page may move.
const time = (page: Page) => page.locator('.anatomy [data-part="time · model"] .clock').textContent();

test.describe('the running time', () => {
  test.use({ viewport: { width: 1280, height: 900 }, reducedMotion: 'no-preference' });

  test('counts up a second at a time from 2m 56s', async ({ page }) => {
    await page.goto('/');
    await page.locator('.anatomy').scrollIntoViewIfNeeded();
    await expect.poll(() => time(page), { timeout: 4000 }).toBe('2m 58s');
  });

  test('holds when Stop is pressed', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('button', { name: 'Stop the animations' }).click();
    const held = await time(page);
    await page.waitForTimeout(2200);
    expect(await time(page)).toBe(held);
  });
});

test.describe('with motion reduced', () => {
  test.use({ reducedMotion: 'reduce' });
  test('the running time holds at 2m 56s', async ({ page }) => {
    await page.goto('/');
    await page.waitForTimeout(2200);
    expect(await time(page)).toBe('2m 56s');
  });
});

test.describe('without scripts', () => {
  test.use({ javaScriptEnabled: false });
  test('the running time reads 2m 56s', async ({ page }) => {
    await page.goto('/');
    expect(await time(page)).toBe('2m 56s');
  });
});
