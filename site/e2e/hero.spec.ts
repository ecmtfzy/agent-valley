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

// With a mouse the hero's panel behaves as the app's: a pointer resting on the bar opens it, one
// leaving the panel shuts it, one only crossing the bar does nothing.
test.describe('pointing at the notch', () => {
  test.use({ viewport: { width: 1280, height: 800 } });
  const screen = (page: import('@playwright/test').Page) => page.locator('.screen');
  const centre = async (page: import('@playwright/test').Page, selector: string) => {
    const box = (await page.locator(selector).boundingBox())!;
    return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
  };
  const ready = async (page: import('@playwright/test').Page) => {
    await page.goto('/');
    await expect(screen(page)).toHaveAttribute('data-opened', '', { timeout: 2000 });
  };
  // A place beside the picture, off it.
  const away = async (page: import('@playwright/test').Page) => {
    const box = (await screen(page).boundingBox())!;
    await page.mouse.move(box.x - 20, box.y + box.height / 2);
  };

  test('a pointer that leaves the panel shuts it, and one resting on the bar opens it again', async ({ page }) => {
    await ready(page);
    const panel = await centre(page, '.screen .panel');
    await page.mouse.move(panel.x, panel.y);
    await away(page);
    await expect(screen(page)).toHaveAttribute('data-state', 'shut');
    const bar = await centre(page, '.bar-hit');
    await page.mouse.move(bar.x, bar.y);
    await expect(screen(page)).toHaveAttribute('data-state', 'open');
    await expect(page.getByRole('button', { name: 'The notch: the AgentValley panel' })).toHaveAttribute('aria-expanded', 'true');
  });

  test('a pointer that never came in leaves the panel open', async ({ page }) => {
    await ready(page);
    await away(page);
    await page.mouse.move(200, 600);
    await page.waitForTimeout(500);
    await expect(screen(page)).toHaveAttribute('data-state', 'open');
  });

  test('a pointer only crossing the bar does not open it', async ({ page }) => {
    await ready(page);
    const panel = await centre(page, '.screen .panel');
    await page.mouse.move(panel.x, panel.y);
    await away(page);
    await expect(screen(page)).toHaveAttribute('data-state', 'shut');
    const bar = await centre(page, '.bar-hit');
    await page.mouse.move(bar.x, bar.y);
    await away(page);
    await page.waitForTimeout(400);
    await expect(screen(page)).toHaveAttribute('data-state', 'shut');
  });

  test('pressed shut, it stays shut under the resting pointer until the pointer goes and comes back', async ({ page }) => {
    await ready(page);
    const notch = page.getByRole('button', { name: 'The notch: the AgentValley panel' });
    await notch.click();
    await page.waitForTimeout(400);
    await expect(screen(page)).toHaveAttribute('data-state', 'shut');
    const bar = await centre(page, '.bar-hit');
    await away(page);
    await page.mouse.move(bar.x, bar.y);
    await expect(screen(page)).toHaveAttribute('data-state', 'open');
  });

  test('Esc shuts the panel the pointer is in', async ({ page }) => {
    await ready(page);
    const panel = await centre(page, '.screen .panel');
    await page.mouse.move(panel.x, panel.y);
    await page.keyboard.press('Escape');
    await expect(screen(page)).toHaveAttribute('data-state', 'shut');
  });

  test('Esc with the pointer on the bar keeps it shut while the pointer rests there', async ({ page }) => {
    await ready(page);
    const bar = await centre(page, '.bar-hit');
    await page.mouse.move(bar.x, bar.y);
    await page.keyboard.press('Escape');
    await page.waitForTimeout(400);
    await expect(screen(page)).toHaveAttribute('data-state', 'shut');
  });

  test('a pointer passing over the picture while it first opens does not leave it shut', async ({ page }) => {
    await page.goto('/');
    // The button shows once React is here, the moment the 400 ms before the first opening start.
    await page.locator('.bar-hit').waitFor();
    const panel = await centre(page, '.screen .panel');
    await page.mouse.move(panel.x, panel.y);
    await away(page);
    await page.waitForTimeout(1000);
    await expect(screen(page)).toHaveAttribute('data-state', 'open');
  });
});

test.describe('on a touch screen', () => {
  test.use({ viewport: { width: 390, height: 844 }, hasTouch: true });
  test('a tap on the notch shuts the panel, and it stays shut', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('.screen')).toHaveAttribute('data-opened', '', { timeout: 2000 });
    await page.getByRole('button', { name: 'The notch: the AgentValley panel' }).tap();
    await page.waitForTimeout(500);
    await expect(page.locator('.screen')).toHaveAttribute('data-state', 'shut');
  });
});

test('at the top the bar wears the block-letter name alone; down the page, only the crew in the notch', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('/');
  const bar = page.locator('header.nav');
  const home = bar.getByRole('link', { name: 'AgentValley', exact: true });
  const mark = home.locator('img[src="/mark.svg"]');
  const name = home.locator('svg.wordmark');
  await expect(name).toBeVisible();
  await expect(mark).toBeHidden();
  await expect(bar.getByText('A small valley of programmers in your notch.')).toHaveCount(0);
  await expect(bar.getByRole('link', { name: 'Words on this page' })).toHaveCount(0);
  for (const label of ['AgentValley on GitHub', 'Install']) await expect(bar.getByRole('link', { name: label })).toBeVisible();
  await page.mouse.wheel(0, 600);
  await expect(name).toBeHidden();
  await expect(mark).toBeVisible();
  await expect(home).toHaveAccessibleName('AgentValley');
  await page.evaluate(() => scrollTo(0, 0));
  await expect(name).toBeVisible();
  await expect(mark).toBeHidden();
});

test('a narrow phone wears the name at the top and the crew down the page', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 800 });
  await page.goto('/');
  const home = page.locator('header.nav').getByRole('link', { name: 'AgentValley', exact: true });
  await expect(home.locator('svg.wordmark')).toBeVisible();
  await expect(home.locator('img[src="/mark.svg"]')).toBeHidden();
  await page.mouse.wheel(0, 600);
  await expect(home.locator('svg.wordmark')).toBeHidden();
  await expect(home.locator('img[src="/mark.svg"]')).toBeVisible();
});

test('the narrowest phone has room for the crew alone', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 800 });
  await page.goto('/');
  const home = page.locator('header.nav').getByRole('link', { name: 'AgentValley', exact: true });
  await expect(home.locator('img[src="/mark.svg"]')).toBeVisible();
  await expect(home.locator('svg.wordmark')).toBeHidden();
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

test('the footer signs off with the block-letter name alone', async ({ page }) => {
  await page.goto('/');
  const foot = page.locator('footer');
  await expect(foot.locator('img[src="/mark.svg"]')).toHaveCount(0);
  await expect(foot.getByRole('img', { name: 'AgentValley' })).toBeVisible();
  await expect(foot.locator('svg.wordmark')).toBeVisible();
});

test('under the crew photo, the coffee line and Sponsor the crew with the mug', async ({ page }) => {
  await page.goto('/');
  const credits = page.locator('section.credits');
  await expect(credits.getByText("The app is free. Their coffee isn't.", { exact: true })).toBeVisible();
  const sponsor = credits.getByRole('link', { name: 'Sponsor the crew' });
  await expect(sponsor).toHaveAttribute('href', 'https://github.com/sponsors/morsechimwai');
  expect((await sponsor.boundingBox())!.height).toBeGreaterThanOrEqual(44);
  await expect(sponsor.locator('.steam img')).toHaveCount(2);
});

test('the footer offers Sponsor the crew as a button with the mug', async ({ page }) => {
  await page.goto('/');
  const sponsor = page.locator('footer').getByRole('link', { name: 'Sponsor the crew' });
  await expect(sponsor).toHaveAttribute('href', 'https://github.com/sponsors/morsechimwai');
  expect(await sponsor.evaluate((el) => getComputedStyle(el).borderTopWidth)).not.toBe('0px');
  expect((await sponsor.boundingBox())!.height).toBeGreaterThanOrEqual(44);
  await expect(sponsor.locator('.steam img')).toHaveCount(2);
});
