import { expect, test } from 'vitest';
import { isHalloween } from '@/lib/halloween';

// The decorations are up from 19 October to the end of 1 November 2026, by the visitor's own clock.
const at = (s: string) => new Date(s); // no Z: local time, as a visitor's clock reads
test.each([
  ['2026-10-18T23:59:59', false],
  ['2026-10-19T00:00:00', true],
  ['2026-10-31T20:00:00', true],
  ['2026-11-01T23:59:59', true],
  ['2026-11-02T00:00:00', false],
  ['2027-10-31T12:00:00', false],
])('%s → %s', (s, on) => expect(isHalloween(at(s))).toBe(on));
