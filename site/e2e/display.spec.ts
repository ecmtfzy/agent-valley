import { expect, type Page, test } from '@playwright/test';

// Another display, in Also in the panel: the line, the issue it came from, and the notch gliding over its still.
const reach = async (page: Page) => {
  await page.goto('/');
  await page.locator('section.also').scrollIntoViewIfNeeded();
};
const sign = (page: Page) => page.getByRole('img', { name: /^A big display with a MacBook in front of it\./ });

test('the line names the setting and links the issue that asked for it', async ({ page }) => {
  await reach(page);
  const also = page.locator('section.also');
  await expect(also.getByText('Another display', { exact: true })).toBeVisible();
  await expect(also.getByText(/Settings › General › Display moves us to the top of the big one/)).toBeVisible();
  await expect(also.getByRole('link', { name: 'issue #1' })).toHaveAttribute('href', 'https://github.com/morsechimwai/agent-valley/issues/1');
  await expect(sign(page)).toBeVisible();
  await expect.poll(() => page.locator('.d-still').evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth)).toBe(720);
});

test.describe('where the page may move', () => {
  test.use({ viewport: { width: 1280, height: 800 }, reducedMotion: 'no-preference' });

  test('the motion plays over the still, and Stop leaves the still', async ({ page }) => {
    await reach(page);
    await page.locator('.d-player').waitFor();
    // No paper of its own, as the crew's: a still left showing would show the notch twice.
    await expect(page.locator('.d-still')).toBeHidden();
    const first = await page.locator('.d-figure').screenshot();
    await page.waitForTimeout(1500);
    expect(first.equals(await page.locator('.d-figure').screenshot())).toBe(false);
    await page.getByRole('button', { name: 'Stop the animations' }).dispatchEvent('click');
    await expect(page.locator('.d-player')).toHaveCount(0);
    await expect(page.locator('.d-still')).toBeVisible();
  });
});

test.describe('reduced motion', () => {
  test.use({ reducedMotion: 'reduce' });
  test('still only', async ({ page }) => {
    await reach(page);
    await page.waitForTimeout(800);
    await expect(page.locator('.d-still')).toBeVisible();
    await expect(page.locator('.d-player')).toHaveCount(0);
  });
});
