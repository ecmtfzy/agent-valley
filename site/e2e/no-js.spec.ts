import { expect, test } from '@playwright/test';

// A reader with scripts off reads the whole page; only what needs a script is gone.
test.use({ javaScriptEnabled: false });

test('the page reads without scripts', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Meet the crew.' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Words on this page.' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Copy' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Stop the animations' })).toHaveCount(0);
  await expect(page.locator('figure:has(.hist)')).toBeHidden();
  await expect(page.locator('.screen')).toHaveAttribute('data-state', 'open');
  expect(await page.locator('.screen .panel').evaluate((el) => getComputedStyle(el).clipPath)).not.toContain('22.34%');
  expect(await page.locator('.term').evaluateAll((all) => all.map((t) => getComputedStyle(t).opacity))).toEqual(['1', '1', '1', '1', '1']);
  for (const shown of await page.locator('.reveal').all()) {
    await shown.scrollIntoViewIfNeeded();
    expect(await shown.evaluate((el) => getComputedStyle(el).opacity)).toBe('1');
  }
});

test('without scripts the bill stands whole, clear of its heading', async ({ page }) => {
  await page.goto('/');
  const sheet = page.locator('.r-sheet');
  await sheet.scrollIntoViewIfNeeded();
  await expect.poll(() => sheet.evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth > 0)).toBe(true);
  // What shows of it, inside every box that clips it, against its own height.
  const [seen, tall] = await sheet.evaluate((img: HTMLImageElement) => {
    const r = img.getBoundingClientRect();
    let [top, bottom] = [r.top, r.bottom];
    for (let e = img.parentElement; e && e !== document.body; e = e.parentElement) {
      if (getComputedStyle(e).overflowY === 'visible') continue;
      const c = e.getBoundingClientRect();
      [top, bottom] = [Math.max(top, c.top), Math.min(bottom, c.bottom)];
    }
    return [Math.round(bottom - top), Math.round(img.offsetHeight)];
  });
  expect(seen).toBe(tall);
  const bill = (await sheet.boundingBox())!;
  const h3 = (await page.getByRole('heading', { name: 'Hand the month over as a PDF.' }).boundingBox())!;
  expect(bill.y + bill.height <= h3.y || h3.y + h3.height <= bill.y).toBe(true);
  // With no panel to point at, no note.
  await expect(page.locator('section.costs .c-note')).toBeHidden();
});
