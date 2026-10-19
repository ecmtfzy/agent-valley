import { expect, type Page, test } from '@playwright/test';

// Meet the crew: one session's org chart playing over its still, wide or tall to fit.
const reach = async (page: Page) => {
  await page.goto('/');
  await page.locator('section.crew').scrollIntoViewIfNeeded();
};
const width = (page: Page) => page.locator('.c-still').evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth);

test('the crew comes right after the problem, with its still', async ({ page }) => {
  await reach(page);
  const order = await page.locator('main > section, body > section').evaluateAll((all) => all.map((s) => s.className));
  const crew = order.findIndex((c) => c.includes('crew'));
  expect(order[crew - 1]).toContain('problem');
  await expect(page.getByRole('img', { name: /^One session at work, drawn as an org chart\./ })).toBeVisible();
  await expect.poll(() => width(page)).toBe(2400);
});

test('a phone gets the tall still', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await reach(page);
  await expect.poll(() => width(page)).toBe(1280);
});

test.describe('where the page may move', () => {
  test.use({ viewport: { width: 1280, height: 800 }, reducedMotion: 'no-preference' });

  test('the motion plays over the still, and Stop leaves the still', async ({ page }) => {
    await reach(page);
    await page.locator('.c-player').waitFor();
    const first = await page.locator('.c-figure').screenshot();
    await page.waitForTimeout(1500);
    expect(first.equals(await page.locator('.c-figure').screenshot())).toBe(false);
    await page.getByRole('button', { name: 'Stop the animations' }).dispatchEvent('click');
    await expect(page.locator('.c-player')).toHaveCount(0);
    await expect(page.locator('.c-still')).toBeVisible();
  });
});

test.describe('reduced motion', () => {
  test.use({ reducedMotion: 'reduce' });
  test('still only', async ({ page }) => {
    await reach(page);
    await page.waitForTimeout(800);
    await expect(page.locator('.c-still')).toBeVisible();
    await expect(page.locator('.c-player')).toHaveCount(0);
  });
});
