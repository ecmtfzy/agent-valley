import { expect, test } from '@playwright/test';

// Get updates: the email box answers by itself, and still posts without scripts.
const box = (page: import('@playwright/test').Page) => page.locator('#updates');

test('an email goes in and the box says so', async ({ page }) => {
  let sent = '';
  await page.route('**/api/subscribe', (route) => {
    sent = route.request().postData() ?? '';
    return route.fulfill({ json: { ok: true } });
  });
  await page.goto('/');
  await box(page).getByLabel('Your email').fill('reader@example.com');
  await box(page).getByRole('button', { name: 'Get updates' }).click();
  await expect(box(page).getByRole('status')).toHaveText("You're on the list. See you at the next version.");
  expect(new URLSearchParams(sent).get('email')).toBe('reader@example.com');
  await expect(box(page).getByRole('button', { name: 'Get updates' })).toBeDisabled();
});

test('when the list is out of reach, the box says to try again', async ({ page }) => {
  await page.route('**/api/subscribe', (route) => route.fulfill({ status: 502, json: { ok: false } }));
  await page.goto('/');
  await box(page).getByLabel('Your email').fill('reader@example.com');
  await box(page).getByRole('button', { name: 'Get updates' }).click();
  await expect(box(page).getByRole('status')).toHaveText('That one got away from us. Try again in a minute.');
  await expect(box(page).getByRole('button', { name: 'Get updates' })).toBeEnabled();
});

test.describe('without scripts', () => {
  test.use({ javaScriptEnabled: false });
  test('the form still posts to the list', async ({ page }) => {
    await page.goto('/');
    const form = box(page).locator('form');
    await expect(form).toHaveAttribute('action', '/api/subscribe');
    await expect(form).toHaveAttribute('method', 'post');
  });
});
