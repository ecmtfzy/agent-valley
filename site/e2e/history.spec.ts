import { expect, test } from '@playwright/test';

test.use({ timezoneId: 'Asia/Bangkok' });

test("History is drawn on the reader's own calendar", async ({ page }) => {
  await page.clock.setFixedTime(new Date('2026-10-16T15:30:00+07:00'));
  await page.goto('/');
  const hist = page.getByRole('group', { name: 'The History page' });
  await expect(hist.locator('.h-title')).toHaveText('October 2026');
  await expect(hist.locator('.h-total b')).toHaveText('$1,261.12');
  await hist.getByRole('button', { name: 'Week' }).click();
  await expect(page.locator('#said')).toHaveText('October 12 – 18, 2026, $467.41');
  await hist.getByRole('button', { name: /^shop-web/ }).click();
  await expect(hist.getByRole('button', { name: 'All projects' })).toBeFocused();
});

test('the arrows keep the keyboard', async ({ page }) => {
  await page.clock.setFixedTime(new Date('2026-10-16T15:30:00+07:00'));
  await page.goto('/');
  const hist = page.getByRole('group', { name: 'The History page' });
  await hist.getByRole('button', { name: 'Earlier' }).click();
  await expect(hist.locator('.h-title')).toHaveText('September 2026');
  await expect(hist.getByRole('button', { name: 'Earlier' })).toBeFocused();
  await hist.getByRole('button', { name: 'Earlier' }).click();
  // Two months back the earlier arrow is off; the keyboard moves to the later one.
  await expect(hist.getByRole('button', { name: 'Earlier' })).toBeDisabled();
  await expect(hist.getByRole('button', { name: 'Later' })).toBeFocused();
});

test('a day picked from the list shows its hours', async ({ page }) => {
  await page.clock.setFixedTime(new Date('2026-10-16T15:30:00+07:00'));
  await page.goto('/');
  const hist = page.getByRole('group', { name: 'The History page' });
  // A list's name is its label, Day, followed by the choice it shows.
  const days = hist.getByRole('combobox', { name: /^Day\b/ });
  await days.selectOption((await days.locator('option', { hasText: 'October 14 ·' }).getAttribute('value'))!);
  await expect(page.locator('#said')).toHaveText(/^October 2026, \$1,261\.12; October 14, \$/);
  await expect(hist.getByRole('combobox', { name: /^Hour\b/ })).toBeVisible();
});

test('the built page holds no History numbers', async ({ request }) => {
  const html = await (await request.get('/')).text();
  expect(html).not.toContain('h-total');
});
