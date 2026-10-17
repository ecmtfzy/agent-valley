import { expect, test } from 'vitest';
import { frameAt, progressOf, SCRUB } from '@/lib/scrub';

test('the top of the track is the first frame, the bottom the last', () => {
  expect(frameAt(0)).toBe(SCRUB.start);
  expect(frameAt(1)).toBe(SCRUB.end);
  expect(frameAt(0.5)).toBe(88);
});

test('past either end it holds there', () => {
  expect(frameAt(-3)).toBe(SCRUB.start);
  expect(frameAt(7)).toBe(SCRUB.end);
});

test('progress is how far the track has passed the top of the screen', () => {
  expect(progressOf(0, 9000, 1000)).toBe(0);
  expect(progressOf(-4000, 9000, 1000)).toBe(0.5);
  expect(progressOf(-20000, 9000, 1000)).toBe(1);
  expect(progressOf(300, 9000, 1000)).toBe(0);
  expect(progressOf(-10, 800, 1000)).toBe(0);
});

test('the scroll keeps the pace the report motion was tuned to: about 22 frames a screen', () => {
  expect((SCRUB.end - SCRUB.start) / (SCRUB.screens - 1)).toBeGreaterThan(20);
  expect((SCRUB.end - SCRUB.start) / (SCRUB.screens - 1)).toBeLessThan(25);
});
