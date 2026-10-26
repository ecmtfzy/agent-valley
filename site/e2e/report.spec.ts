import { expect, test, type Locator, type Page } from '@playwright/test';

// The PDF sits in the costs section in one scene with the History panel: the report's first
// page as one picture, out from behind the panel's right edge, under its Export PDF link.

test('the PDF sits in the costs section, just before the funnies, with the sheet', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('section.costs #report')).toHaveCount(1);
  const order = await page.locator('main > section').evaluateAll((all) => all.map((s) => s.className));
  const at = order.findIndex((c) => c.includes('costs'));
  expect(await page.locator('main > section').nth(at + 1).getAttribute('id')).toBe('funnies');
  await expect(page.getByRole('heading', { name: 'Hand the month over as a PDF.' })).toBeVisible();
  await expect(page.getByRole('img', { name: /^The first page of a statement of work for September 2026, all projects: / })).toBeVisible();
  const sheet = page.locator('.r-sheet');
  await sheet.scrollIntoViewIfNeeded();
  await expect.poll(() => sheet.evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth > 0)).toBe(true);
  expect(await sheet.evaluate((img: HTMLImageElement) => [img.naturalWidth, img.naturalHeight].join('x'))).toBe(
    `${await sheet.getAttribute('width')}x${await sheet.getAttribute('height')}`,
  );
});

test('the sheet stands on the page itself, with no box behind it', async ({ page }) => {
  await page.goto('/');
  const sheet = page.locator('.r-sheet');
  await sheet.scrollIntoViewIfNeeded();
  await expect.poll(() => sheet.evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth > 0)).toBe(true);
  expect(await sheet.evaluate((img) => getComputedStyle(img).backgroundColor)).toBe('rgba(0, 0, 0, 0)');
  // Above the tilted paper's left end, the picture is clear.
  const alpha = await sheet.evaluate((img: HTMLImageElement) => {
    const canvas = Object.assign(document.createElement('canvas'), { width: img.naturalWidth, height: img.naturalHeight });
    const pen = canvas.getContext('2d')!;
    pen.drawImage(img, 0, 0);
    return pen.getImageData(4, 4, 1, 1).data[3];
  });
  expect(alpha).toBeLessThan(8);
});

const box = async (l: Locator) => (await l.boundingBox())!;
const meets = (a: { x: number; y: number; width: number; height: number }, b: typeof a) =>
  a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;

// Put the panel's foot `below` px under the foot of the screen (negative: above it). Twice, as
// what loads above it may still move it.
const footAt = async (page: Page, below: number) => {
  for (let i = 0; i < 2; i++) {
    await page.evaluate((below) => {
      const hist = document.querySelector('section.costs .hist')!;
      scrollTo({ top: scrollY + hist.getBoundingClientRect().bottom - innerHeight - below, behavior: 'instant' });
    }, below);
    await page.waitForTimeout(150);
  }
};

// The scene with the panel drawn and the sheet loaded.
const scene = async (page: Page) => {
  await page.goto('/');
  const hist = page.locator('section.costs .hist');
  await hist.scrollIntoViewIfNeeded();
  await expect(hist).toBeVisible();
  const sheet = page.locator('.r-sheet');
  await expect.poll(() => sheet.evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth > 0)).toBe(true);
  // The panel's foot halfway up the screen: the bill all the way out, its transition over.
  await footAt(page, -0.5 * page.viewportSize()!.height);
  await expect(page.locator('section.costs .c-scene')).toHaveAttribute('data-out', '1');
  await page.waitForTimeout(200);
  return { hist, sheet };
};

test.describe('on a wide screen', () => {
  test.use({ viewport: { width: 1280, height: 800 }, reducedMotion: 'no-preference' });

  test('the heading and its words share the top row', async ({ page }) => {
    await page.goto('/');
    const h2 = await box(page.getByRole('heading', { name: 'See what each project cost.' }));
    const lead = await box(page.locator('section.costs .lead'));
    expect(lead.x).toBeGreaterThan(h2.x + h2.width);
    expect(Math.abs(lead.y - h2.y)).toBeLessThanOrEqual(40);
  });

  test('the bill comes out from behind the panel, under the Export PDF link', async ({ page }) => {
    const { hist, sheet } = await scene(page);
    const panel = await box(hist);
    const bill = await box(sheet);
    const top = await box(hist.locator('.h-top'));
    expect(bill.x + bill.width).toBeGreaterThan(panel.x + panel.width);
    expect(bill.x).toBeLessThan(panel.x + panel.width);
    expect(bill.y).toBeGreaterThan(top.y + top.height);
    // The pen note over the panel, its arrow down onto the link.
    const note = page.locator('section.costs .c-note');
    await expect(note).toHaveText('Export PDF');
    expect((await box(note)).y + (await box(note)).height).toBeLessThanOrEqual(panel.y);
    const link = await box(hist.getByRole('link', { name: 'Export PDF' }));
    const pen = await box(note.locator('svg'));
    expect(pen.x + pen.width).toBeGreaterThan(link.x);
    expect(pen.x).toBeLessThan(link.x + link.width);
    // The needs-you section above plays its motion; this one holds the one picture.
    expect(await page.locator('#report img').count()).toBe(1);
    expect(await page.locator('#report [inert]').count()).toBe(0);
  });

  test("the bill never covers the panel's list, whichever list it shows", async ({ page }) => {
    const { hist } = await scene(page);
    const list = hist.locator('.h-list');
    // Each row at its left end, middle and right end: the panel is what is there, not the bill.
    const covered = async () => {
      await list.scrollIntoViewIfNeeded();
      return list.evaluate((el) => {
        const at = [...el.children].flatMap((row) => {
          const r = row.getBoundingClientRect();
          return [r.left + 4, r.left + r.width / 2, r.right - 4].map((x) => [x, r.top + r.height / 2]);
        });
        return [at.length, at.filter(([x, y]) => !el.contains(document.elementFromPoint(x, y))).length];
      });
    };
    const [rows, under] = await covered();
    expect(rows).toBeGreaterThan(0);
    expect(under).toBe(0);
    await hist.getByRole('button', { name: /^shop-web/ }).click();
    await expect(hist.locator('.h-name')).toHaveText('shop-web');
    expect((await covered())[1]).toBe(0);
  });
});

for (const width of [390, 768, 900, 1280]) {
  test(`no sideways scroll at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 800 });
    await scene(page);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  });
}

test.describe('on a phone', () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test('the bill comes after the panel, and the caption is not under it', async ({ page }) => {
    const { hist, sheet } = await scene(page);
    expect((await box(sheet)).y).toBeGreaterThan((await box(hist)).y + (await box(hist)).height / 2);
    expect(meets(await box(page.locator('section.costs figcaption')), await box(sheet))).toBe(false);
  });
});

// How far out the bill is: --t, written on the bill's slot alone.
const out = (page: Page) => page.locator('section.costs .r-slot').evaluate((s: HTMLElement) => Number(s.style.getPropertyValue('--t') || 1));
// How far the bill sits from its place all the way out, once its short transition is over.
const off = async (page: Page) => {
  await page.waitForTimeout(200);
  return page.evaluate(() => {
    const slot = document.querySelector('.r-slot')!.getBoundingClientRect();
    const sheet = document.querySelector('.r-sheet')!.getBoundingClientRect();
    return Math.round(Math.abs(sheet.x - slot.x) + Math.abs(sheet.y - slot.y));
  });
};

// From the bill all the way in, press Export PDF on the panel (a project picked first, or not),
// wait for the smooth scroll to stop: the bill is all the way out there.
const exportPDF = async (page: Page, pick: boolean) => {
  const { hist } = await scene(page);
  if (pick) await hist.getByRole('button', { name: /^shop-web/ }).click();
  await footAt(page, 10);
  await expect.poll(() => out(page)).toBe(0);
  await hist.getByRole('link', { name: 'Export PDF' }).click();
  await settled(page);
  await expect(page.locator('section.costs .c-scene')).toHaveAttribute('data-out', '1');
};
const settled = async (page: Page) => {
  let last = -1;
  await expect.poll(async () => {
    const y = await page.evaluate(() => scrollY);
    const still = y === last;
    last = y;
    return still;
  }, { intervals: [150] }).toBe(true);
};

test.describe('the bill and the scroll', () => {
  test.use({ viewport: { width: 1280, height: 800 }, reducedMotion: 'no-preference' });

  test('the bill comes out as the page goes down and back in as it goes up', async ({ page }) => {
    await scene(page);
    await footAt(page, 10);
    await expect.poll(() => out(page)).toBe(0);
    const behind = await off(page);
    await footAt(page, -0.2 * 800);
    await expect.poll(() => out(page)).toBeGreaterThan(0.3);
    expect(await out(page)).toBeLessThan(0.7);
    const halfway = await off(page);
    await footAt(page, -0.5 * 800);
    await expect(page.locator('section.costs .c-scene')).toHaveAttribute('data-out', '1');
    expect(await off(page)).toBe(0);
    expect(halfway).toBeGreaterThan(0);
    expect(behind).toBeGreaterThan(halfway);
    await footAt(page, 10);
    await expect.poll(() => out(page)).toBe(0);
    await expect(page.locator('section.costs .c-scene')).not.toHaveAttribute('data-out', '1');
  });

  test('Export PDF lands on the bill all the way out', async ({ page }) => {
    await exportPDF(page, false);
  });

  test('Stop puts the bill all the way out and holds it', async ({ page }) => {
    await scene(page);
    await footAt(page, 10);
    await expect.poll(() => out(page)).toBe(0);
    await page.getByRole('button', { name: 'Stop the animations' }).dispatchEvent('click');
    expect(await off(page)).toBe(0);
    await footAt(page, 40);
    expect(await off(page)).toBe(0);
  });
});

test.describe('with motion reduced', () => {
  test.use({ viewport: { width: 1280, height: 800 }, reducedMotion: 'reduce' });

  test('the bill stands all the way out wherever the page is', async ({ page }) => {
    await scene(page);
    await footAt(page, 10);
    expect(await off(page)).toBe(0);
    expect(await out(page)).toBe(1);
  });
});

// A laptop's short screen: the jump to the bill puts the panel's foot higher than on a tall one.
test.describe('on a short screen', () => {
  test.use({ viewport: { width: 1366, height: 650 }, reducedMotion: 'no-preference' });

  test('Export PDF lands on the bill all the way out', async ({ page }) => {
    await exportPDF(page, false);
  });
  test('Export PDF lands on the bill all the way out, a project picked', async ({ page }) => {
    await exportPDF(page, true);
  });
  test('a link straight to the bill opens on it all the way out', async ({ page }) => {
    await page.goto('/#report');
    await expect(page.locator('section.costs .hist')).toBeVisible();
    await settled(page);
    await expect(page.locator('section.costs .c-scene')).toHaveAttribute('data-out', '1');
  });
});

test('from 900px down, the pen note goes: the caption stands between it and the link', async ({ page }) => {
  await page.setViewportSize({ width: 768, height: 900 });
  await scene(page);
  await expect(page.locator('section.costs .c-note')).toBeHidden();
});

test.describe('the bill, the panel and the note', () => {
  test.use({ viewport: { width: 1280, height: 800 }, reducedMotion: 'no-preference' });

  test('the scroll writes on the bill alone, not on the whole scene', async ({ page }) => {
    await scene(page);
    await footAt(page, -0.2 * 800);
    await expect.poll(() => out(page)).toBeLessThan(1);
    expect(await page.locator('section.costs .c-scene').evaluate((s: HTMLElement) => s.style.getPropertyValue('--t'))).toBe('');
  });

  test('a panel that grows without a scroll moves the bill with it', async ({ page }) => {
    const { hist } = await scene(page);
    await footAt(page, -0.25 * 800);
    await expect.poll(() => out(page)).toBeLessThan(1);
    const before = await out(page);
    const y = await page.evaluate(() => scrollY);
    // A project adds its name over the list: the panel's foot goes down.
    await hist.getByRole('button', { name: /^shop-web/ }).click();
    await expect(hist.locator('.h-name')).toHaveText('shop-web');
    expect(await page.evaluate(() => scrollY)).toBe(y);
    await expect.poll(() => out(page)).toBeLessThan(before - 0.02);
  });

  test('before the panel is drawn the bill is all the way out, and goes back in once it is', async ({ page }) => {
    await scene(page);
    await footAt(page, 10);
    await expect.poll(() => out(page)).toBe(0);
    const figure = page.locator('section.costs figure');
    await figure.evaluate((f) => f.setAttribute('hidden', ''));
    await expect.poll(() => out(page)).toBe(1);
    await figure.evaluate((f) => f.removeAttribute('hidden'));
    await expect.poll(() => out(page)).toBe(0);
  });

  test("the note's arrow stays on the link when the panel's buttons grow", async ({ page }) => {
    const { hist } = await scene(page);
    // As a missing font or larger type would: the span buttons wider, the link further left.
    await page.addStyleTag({ content: '.hist .h-seg button{padding-inline:40px !important}' });
    const head = async () => {
      const pen = (await page.locator('section.costs .c-note svg').boundingBox())!;
      return pen.x + (pen.width * 56) / 72;
    };
    await expect.poll(async () => {
      const link = (await hist.getByRole('link', { name: 'Export PDF' }).boundingBox())!;
      const x = await head();
      return x > link.x + 8 && x < link.x + link.width - 8;
    }).toBe(true);
  });
});
