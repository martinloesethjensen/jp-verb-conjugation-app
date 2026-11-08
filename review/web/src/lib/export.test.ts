import { describe, expect, test } from 'vitest';
import type { ReadyEntry } from './api.ts';
import { canStamp, groupReady, idsFromSummary } from './export.ts';

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

const ready = (dataset: string, kind: string, item_id: string, entry_id: string, entry_title: string, title = item_id): ReadyEntry => ({
	dataset,
	kind,
	item_id,
	entry_id,
	entry_title,
	title
});

describe('groupReady', () => {
	test('groups a verb with its ready examples', () => {
		const verb = ready('verbs', 'entry', 'たべる', 'たべる', 'たべる (食べる)');
		const a = ready('verbs', 'example', 'e1aaaa', 'たべる', 'たべる (食べる)', '食べて');
		const b = ready('verbs', 'example', 'e2aaaa', 'たべる', 'たべる (食べる)', '食べた');
		expect(groupReady([verb, a, b])).toEqual([{ key: 'verbs/たべる', title: 'たべる (食べる)', entry: verb, examples: [a, b] }]);
	});
	test('examples without a ready verb form their own group titled by the verb', () => {
		const a = ready('verbs', 'example', 'e1aaaa', 'のむ', 'のむ (飲む)', '飲んで');
		expect(groupReady([a])).toEqual([{ key: 'verbs/のむ', title: 'のむ (飲む)', entry: null, examples: [a] }]);
	});
	test('counters and grammar stay one group each, in the order given', () => {
		const hon = ready('counters', 'entry', 'hon', 'hon', '本');
		const point = ready('grammar', 'entry', 'n-desu', 'n-desu', 'んです');
		expect(groupReady([hon, point]).map((g) => [g.key, g.entry, g.examples.length])).toEqual([
			['counters/hon', hon, 0],
			['grammar/n-desu', point, 0]
		]);
	});
});

describe('canStamp', () => {
	test('entries of four datasets and verb examples', () => {
		for (const d of ['counters', 'grammar', 'verbs', 'words']) expect(canStamp(d, 'entry')).toBe(true);
		expect(canStamp('verbs', 'example')).toBe(true);
		expect(canStamp('grammar', 'example')).toBe(false);
		expect(canStamp('verbs', 'collocation')).toBe(false);
		expect(canStamp('furigana', 'entry')).toBe(false);
	});
});
