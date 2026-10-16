import { expect, test } from 'vitest';
import { dollars, historyView, nextPick, noise, spanTitle, wholeDollars, type Pick, type Span } from '@/lib/history';

// The values are the old page's own, worked out by its script for this same moment.
const now = new Date(2026, 9, 16, 15, 30);
const at = (span: Span, extra: Partial<Pick> = {}): Pick => ({ span, anchor: now, project: null, day: null, hour: null, ...extra });

test('month', () => expect(historyView(at('Month'), now).announce).toBe('October 2026, $1,261.12'));
test('week', () => expect(historyView(at('Week'), now).announce).toBe('October 12 – 18, 2026, $467.41'));
test('day', () => expect(historyView(at('Day'), now).announce).toBe('Friday, October 16, 2026, $42.38'));
test('one project', () => expect(historyView(at('Month', { project: 0 }), now).announce).toBe('October 2026, shop-web, $628.47'));
test('two months back', () => expect(historyView(at('Month', { anchor: new Date(2026, 7, 1) }), now).announce).toBe('August 2026, $2,101.27'));
test('no earlier than two months back', () => expect(historyView(at('Month', { anchor: new Date(2026, 7, 1) }), now).canEarlier).toBe(false));
test('no later than now', () => expect(historyView(at('Month'), now).canLater).toBe(false));
test('money', () => expect([dollars(0), dollars(0.004), dollars(12.5), wholeDollars(0.4), wholeDollars(1234.5)]).toEqual(['$0.00', '<$0.01', '$12.50', '<$1', '$1,235']));
test('titles', () => expect([
  spanTitle('Week', new Date(2026, 8, 28), new Date(2026, 9, 5)),
  spanTitle('Day', new Date(2026, 9, 16), new Date(2026, 9, 17)),
  spanTitle('Month', new Date(2026, 9, 1), new Date(2026, 10, 1)),
]).toEqual(['September 28 – October 4, 2026', 'Friday, October 16, 2026', 'October 2026']));
test('noise', () => expect([noise(0, 20000, 1), noise(3, 20742, 2)]).toEqual([0.24252661713398993, 0.8758266272488981]));
test('picking a day twice clears it', () => {
  const v = String(new Date(2026, 9, 14).getTime());
  const once = nextPick(at('Month'), { a: 'day', v });
  expect(once.day?.getTime()).toBe(+v);
  expect(nextPick(once, { a: 'day', v }).day).toBeNull();
});
test('a picked day and hour join the announcement', () => {
  const day = nextPick(at('Month'), { a: 'day', v: String(new Date(2026, 9, 14).getTime()) });
  const hour = nextPick(day, { a: 'hour', v: '10' });
  expect(historyView(hour, now).announce).toMatch(/^October 2026, \$1,261\.12; October 14, 10:00, \$\d/);
});
test('the list offers All of the span by an empty value', () => {
  const day = nextPick(at('Month'), { a: 'day', v: String(new Date(2026, 9, 14).getTime()) });
  expect(nextPick(day, { a: 'day', v: '' }).day).toBeNull();
});
test('the footnote says since when', () => expect(historyView(at('Month'), now).since).toBe('History since August 1, 2026'));
