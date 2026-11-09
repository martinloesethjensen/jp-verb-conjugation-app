import { expect, test } from 'vitest';
import { shortDate } from './dates.ts';

const now = new Date(2026, 10, 9, 12);

test('a date this year shows day and month', () => {
	expect(shortDate(new Date(2026, 2, 4, 12), now, 'en-GB')).toBe('4 Mar');
});

test('a date in another year adds the year', () => {
	expect(shortDate(new Date(2025, 10, 9, 12), now, 'en-GB')).toBe('9 Nov 2025');
	expect(shortDate(new Date(2027, 0, 1, 12), now, 'en-GB')).toBe('1 Jan 2027');
});
