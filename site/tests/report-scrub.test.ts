import { expect, test } from 'vitest';
import { frameAt, progressOf, SCRUB } from '@/lib/report-scrub';

test('the top of the track is the first frame, the bottom the last', () => {
  expect(frameAt(0)).toBe(SCRUB.start);
  expect(frameAt(1)).toBe(SCRUB.end);
  expect(frameAt(0.5)).toBe(120);
});

test('past either end it holds there', () => {
  expect(frameAt(-3)).toBe(SCRUB.start);
  expect(frameAt(7)).toBe(SCRUB.end);
});

test('progress is how far the track has passed the top of the screen', () => {
  expect(progressOf(0, 11000, 1000)).toBe(0);
  expect(progressOf(-5000, 11000, 1000)).toBe(0.5);
  expect(progressOf(-20000, 11000, 1000)).toBe(1);
  expect(progressOf(300, 11000, 1000)).toBe(0);
  expect(progressOf(-10, 800, 1000)).toBe(0);
});
