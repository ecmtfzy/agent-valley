import { expect, test } from '@playwright/test';

// The PDF section shows the report's first page as one picture: nothing plays and nothing grows.

test('the report section sits between costs and the terminal, with the sheet', async ({ page }) => {
  await page.goto('/');
  const order = await page.locator('main > section').evaluateAll((all) => all.map((s) => s.className));
  const at = order.findIndex((c) => c.includes('report'));
  expect(order[at - 1]).toContain('costs');
  expect(order[at + 1]).toContain('terminal');
  await expect(page.getByRole('heading', { name: 'Hand the month over as a PDF.' })).toBeVisible();
  await expect(page.getByRole('img', { name: /^The first page of a statement of work for September 2026, all projects: / })).toBeVisible();
  const sheet = page.locator('.r-sheet');
  await sheet.scrollIntoViewIfNeeded();
  await expect.poll(() => sheet.evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth > 0)).toBe(true);
  expect(await sheet.evaluate((img: HTMLImageElement) => [img.naturalWidth, img.naturalHeight].join('x'))).toBe(
    `${await sheet.getAttribute('width')}x${await sheet.getAttribute('height')}`,
  );
});

test('the sheet stands on the page itself, with no box behind it', async ({ page }) => {
  await page.goto('/');
  const sheet = page.locator('.r-sheet');
  await sheet.scrollIntoViewIfNeeded();
  await expect.poll(() => sheet.evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth > 0)).toBe(true);
  expect(await sheet.evaluate((img) => getComputedStyle(img).backgroundColor)).toBe('rgba(0, 0, 0, 0)');
  // Above the tilted paper's left end, the picture is clear.
  const alpha = await sheet.evaluate((img: HTMLImageElement) => {
    const canvas = Object.assign(document.createElement('canvas'), { width: img.naturalWidth, height: img.naturalHeight });
    const pen = canvas.getContext('2d')!;
    pen.drawImage(img, 0, 0);
    return pen.getImageData(4, 4, 1, 1).data[3];
  });
  expect(alpha).toBeLessThan(8);
});

test.describe('where the page may move', () => {
  test.use({ viewport: { width: 1280, height: 800 }, reducedMotion: 'no-preference' });

  test('the section is as tall as its content, and plays nothing', async ({ page }) => {
    await page.goto('/');
    await page.locator('section.report').scrollIntoViewIfNeeded();
    await page.waitForLoadState('networkidle');
    expect(await page.locator('section.report').evaluate((s: HTMLElement) => s.offsetHeight / innerHeight)).toBeLessThan(1.5);
    // The needs-you section above plays its motion; this one holds the one picture.
    expect(await page.locator('section.report img').count()).toBe(1);
    expect(await page.locator('section.report [inert]').count()).toBe(0);
  });
});
