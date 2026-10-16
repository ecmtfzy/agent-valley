import { expect, test } from '@playwright/test';

test('the notch shuts and opens the panel, and the picture says so', async ({ page }) => {
  await page.goto('/');
  const notch = page.getByRole('button', { name: 'The notch: the AgentValley panel' });
  await expect(page.locator('.screen')).toHaveAttribute('data-state', 'open');
  await notch.click();
  await expect(notch).toHaveAttribute('aria-expanded', 'false');
  await expect(page.locator('.screen > [role=img]')).toHaveAttribute('aria-label', 'The top of a MacBook screen. Beside the notch, a waving programmer and a red 1: an agent needs you. Below, the crew stands in the valley.');
  await notch.press('Enter');
  await expect(page.locator('.screen')).toHaveAttribute('data-state', 'open');
});

test('the top bar is the crew and the name in plain type, without the motto', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('/');
  const bar = page.locator('header.nav');
  const home = bar.getByRole('link', { name: 'AgentValley', exact: true });
  await expect(home).toHaveText('AgentValley');
  await expect(home.locator('img[src="/mark.svg"]')).toBeVisible();
  await expect(bar.locator('svg.wordmark')).toHaveCount(0);
  await expect(bar.getByText('A small valley of programmers in your notch.')).toHaveCount(0);
  await expect(bar.getByRole('link', { name: 'Words on this page' })).toHaveCount(0);
  for (const name of ['AgentValley on GitHub', 'Install']) await expect(bar.getByRole('link', { name })).toBeVisible();
});

test('the animations switch on the top bar is an icon that names itself on hover', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('/');
  const stop = page.getByRole('button', { name: 'Stop the animations' });
  await expect(stop).toHaveAttribute('title', 'Stop the animations');
  expect((await stop.boundingBox())!.width).toBeLessThan(50);
  await stop.click();
  await expect(page.getByRole('button', { name: 'Play the animations' })).toHaveAttribute('title', 'Play the animations');
});

for (const width of [320, 390, 1280]) {
  test(`the top bar is one row that stays at the top, and Install lands below it, at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 800 });
    await page.goto('/');
    const bar = page.locator('header.nav');
    expect((await bar.boundingBox())!.height).toBeLessThan(80);
    await bar.getByRole('link', { name: 'Install' }).click();
    await page.waitForTimeout(300);
    const { top, under } = await page.evaluate(() => ({
      top: document.querySelector('header.nav')!.getBoundingClientRect().top,
      under: document.querySelector('header.nav')!.getBoundingClientRect().bottom,
    }));
    expect(top).toBe(0);
    expect(await page.locator('#install').evaluate((el) => el.getBoundingClientRect().top)).toBeGreaterThanOrEqual(under - 1);
  });
}

test('a phone keeps GitHub off the top bar', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 800 });
  await page.goto('/');
  const bar = page.locator('header.nav');
  await expect(bar.getByRole('link', { name: 'AgentValley on GitHub' })).toBeHidden();
  await expect(bar.getByRole('button', { name: 'Stop the animations' })).toBeVisible();
});

test('the hero says, in a badge of its own, that the app is for Claude Code alone', async ({ page }) => {
  await page.goto('/');
  const badge = page.locator('.hero').getByText('Only for Claude Code, on Mac', { exact: true });
  await expect(badge).toBeVisible();
  expect(await badge.evaluate((el) => getComputedStyle(el).borderTopWidth)).not.toBe('0px');
  await expect(page.locator('.hero img[alt*="Claude" i], .hero svg[aria-label*="Claude" i]')).toHaveCount(0);
});

test('the footer signs off with the full logo: the crew and the block-letter name', async ({ page }) => {
  await page.goto('/');
  const foot = page.locator('footer');
  await expect(foot.locator('img[src="/mark.svg"]')).toBeVisible();
  await expect(foot.getByRole('img', { name: 'AgentValley' })).toBeVisible();
  await expect(foot.locator('svg.wordmark')).toBeVisible();
});

test('the footer offers Sponsor the crew as a button with the mug', async ({ page }) => {
  await page.goto('/');
  const sponsor = page.locator('footer').getByRole('link', { name: 'Sponsor the crew' });
  await expect(sponsor).toHaveAttribute('href', 'https://github.com/sponsors/morsechimwai');
  expect(await sponsor.evaluate((el) => getComputedStyle(el).borderTopWidth)).not.toBe('0px');
  expect((await sponsor.boundingBox())!.height).toBeGreaterThanOrEqual(44);
  await expect(sponsor.locator('.steam img')).toHaveCount(2);
});
