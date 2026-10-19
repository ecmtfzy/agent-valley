import { expect, test } from '@playwright/test';

// The Valley Funnies on the home page: its nameplate on the top bar and a cutting near the end.
test('the top bar names the paper and leads to it', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('/');
  const plate = page.locator('header.nav').getByRole('link', { name: 'The Valley Funnies' });
  await expect(plate).toHaveAttribute('href', '/comics/');
  await expect(plate).toBeVisible();
});

test('the cutting shows three strips, each leading to its page, and the way to all of them', async ({ page }) => {
  await page.goto('/');
  const cutting = page.locator('#funnies');
  await expect(cutting.getByRole('heading', { level: 2, name: 'The Valley Funnies' })).toBeVisible();
  await expect(cutting.locator('article')).toHaveCount(3);
  for (const slug of ['lunch-break', 'explore', 'tab-7']) await expect(cutting.locator(`a[href="/comics/${slug}/"]`)).toHaveCount(1);
  await expect(cutting.getByRole('link', { name: /^Read all \d+ strips$/ })).toHaveAttribute('href', '/comics/');
});
