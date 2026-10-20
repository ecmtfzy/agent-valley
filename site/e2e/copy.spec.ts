import { expect, test } from '@playwright/test';

test('copy says Copied', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.goto('/');
  const box = page.locator('.command').first();
  await box.getByRole('button', { name: 'Copy' }).click();
  await expect(box.getByRole('button')).toHaveText('Copied');
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe('brew install --cask morsechimwai/tap/agent-valley');
  await expect(box.getByRole('button')).toHaveText('Copy', { timeout: 3000 });
});

test('a refused clipboard selects the command instead', async ({ page }) => {
  await page.addInitScript(() => { navigator.clipboard.writeText = () => Promise.reject(new Error('no')); });
  await page.goto('/');
  const box = page.locator('.command').first();
  await box.getByRole('button', { name: 'Copy' }).click();
  await expect(box.getByRole('button')).toHaveText(/Press (⌘C|Ctrl\+C)/);
  expect(await page.evaluate(() => getSelection()?.toString())).toBe('brew install --cask morsechimwai/tap/agent-valley');
});

test('the button is described by the command it copies', async ({ page }) => {
  await page.goto('/');
  const box = page.locator('.command').first();
  await expect(box.getByRole('button', { name: 'Copy' })).toHaveAccessibleDescription('brew install --cask morsechimwai/tap/agent-valley');
});

test('stop the animations is remembered', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'Stop the animations' }).click();
  await page.reload();
  await expect(page.locator('html')).toHaveClass(/still/);
  await expect(page.getByRole('button', { name: 'Play the animations' })).toBeVisible();
});
