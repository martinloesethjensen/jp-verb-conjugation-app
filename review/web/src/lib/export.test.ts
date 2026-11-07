import { describe, expect, test } from 'vitest';
import { idsFromSummary } from './export.ts';

describe('idsFromSummary', () => {
	test('reads the last line of a review-pull summary', () => {
		expect(idsFromSummary('Site suggestion ids: 12, 13, 40. Stamp ids: 3.')).toEqual({ suggestions: [12, 13, 40], stamps: [3] });
	});
	test('none and a whole pasted summary', () => {
		const summary = '## Review pull\n\n### Changes\n\n- Changed 傘 (Sato)\n\nSite suggestion ids: 7. Stamp ids: none.\n';
		expect(idsFromSummary(summary)).toEqual({ suggestions: [7], stamps: [] });
	});
	test('anything else gives nothing', () => {
		expect(idsFromSummary('12, 13')).toEqual({ suggestions: [], stamps: [] });
	});
});
