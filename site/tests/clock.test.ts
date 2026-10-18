import { expect, test } from 'vitest';
import { elapsed } from '@/lib/clock';

// As the app writes a running time (Format.elapsed in PanelView.swift).
test('a running time reads as the app writes it', () => {
  expect(elapsed(56)).toBe('56s');
  expect(elapsed(68)).toBe('1m 08s');
  expect(elapsed(176)).toBe('2m 56s');
  expect(elapsed(599)).toBe('9m 59s');
  expect(elapsed(600)).toBe('10m');
  expect(elapsed(3599)).toBe('59m');
  expect(elapsed(3600)).toBe('1h 00m');
  expect(elapsed(3725)).toBe('1h 02m');
});
