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
  for (const shown of await page.locator('.reveal').all()) {
    await shown.scrollIntoViewIfNeeded();
    expect(await shown.evaluate((el) => getComputedStyle(el).opacity)).toBe('1');
  }
});
