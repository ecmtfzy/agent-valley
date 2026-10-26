import { expect, test } from '@playwright/test';

// Get updates: the email box asks the mailbox for a yes, answers by itself, and still posts
// without scripts.
const box = (page: import('@playwright/test').Page) => page.locator('#updates');

test('an email gets a link to confirm, and the box says to look', async ({ page }) => {
  let sent = '';
  await page.route('**/api/subscribe', (route) => {
    sent = route.request().postData() ?? '';
    return route.fulfill({ json: { ok: true, said: 'sent' } });
  });
  await page.goto('/');
  await box(page).getByLabel('Your email').fill('reader@example.com');
  await box(page).getByRole('button', { name: 'Get updates' }).click();
  await expect(box(page).getByRole('status')).toHaveText("Check your inbox. One click there and you're on the list.");
  expect(new URLSearchParams(sent).get('email')).toBe('reader@example.com');
  // Sunny pops up with the letter and names the address; Got it puts him away.
  const letter = page.getByRole('dialog', { name: 'Check your inbox.' });
  await expect(letter).toContainText('reader@example.com');
  await letter.getByRole('button', { name: 'Got it' }).click();
  await expect(letter).toBeHidden();
  await expect(box(page).getByRole('button', { name: 'Get updates' })).toBeDisabled();
});

test('when the list is out of reach, the box says to try again', async ({ page }) => {
  await page.route('**/api/subscribe', (route) => route.fulfill({ status: 502, json: { ok: false, said: 'failed' } }));
  await page.goto('/');
  await box(page).getByLabel('Your email').fill('reader@example.com');
  await box(page).getByRole('button', { name: 'Get updates' }).click();
  await expect(box(page).getByRole('status')).toHaveText('That one got away from us. Try again in a minute.');
  await expect(box(page).getByRole('button', { name: 'Get updates' })).toBeEnabled();
});

test("when the day's mail is gone, the box says come back tomorrow", async ({ page }) => {
  await page.route('**/api/subscribe', (route) => route.fulfill({ status: 502, json: { ok: false, said: 'full' } }));
  await page.goto('/');
  await box(page).getByLabel('Your email').fill('reader@example.com');
  await box(page).getByRole('button', { name: 'Get updates' }).click();
  await expect(box(page).getByRole('status')).toHaveText("We've sent all the mail we can for today. Try again tomorrow.");
});

test.describe('without scripts', () => {
  // Without reduced motion the page scrolls smoothly; with scripts off, Chrome can stall that
  // scroll under load and the click waits for a button that never stops moving.
  test.use({ javaScriptEnabled: false, reducedMotion: 'reduce' });
  // The page's own policy must let the form post here, or the browser drops the press.
  test('the form still posts to the list', async ({ page }) => {
    let sent = '';
    await page.route('**/api/subscribe', (route) => {
      sent = route.request().postData() ?? '';
      return route.fulfill({ contentType: 'text/html', body: "<p>Check your inbox. One click there and you're on the list.</p>" });
    });
    await page.goto('/');
    await box(page).getByLabel('Your email').fill('reader@example.com');
    await box(page).getByRole('button', { name: 'Get updates' }).click();
    await expect(page.getByText('Check your inbox.')).toBeVisible();
    expect(new URLSearchParams(sent).get('email')).toBe('reader@example.com');
  });
});
