import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

// WCAG AAA, as the old page held, with the panel open and shut.
const check = (page: import('@playwright/test').Page) =>
  new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag2aaa']).analyze();

test.use({ reducedMotion: 'reduce' });

test('no AAA violations with the panel open', async ({ page }) => {
  await page.goto('/');
  await page.locator('.hist .h-title').waitFor();
  const { violations } = await check(page);
  expect(violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(', ')}`)).toEqual([]);
});

test('no AAA violations with the panel shut', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'The notch: the AgentValley panel' }).click();
  const { violations } = await check(page);
  expect(violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(', ')}`)).toEqual([]);
});
