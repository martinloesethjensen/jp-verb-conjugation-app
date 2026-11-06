import { describe, expect, test } from 'vitest';
import { addFieldsOf, entryId, entryTitle, leftBehind, partOf, partsOf, unknownKanjiRuns } from './targets.ts';

const point = {
	id: 'te-iru',
	title: 'ている',
	usages: [{ id: 'usage1', heading: 'h', explanation: 'e', examples: [{ id: 'ex1', jp: 'a', en: 'a' }] }],
	pitfalls: [{ id: 'pit1', heading: 'h', explanation: 'e', examples: [{ id: 'ex2', jp: 'b', en: 'b' }] }],
	contrasts: [{ id: 'other-point', pattern: 'p', explanation: 'e', examples: [{ id: 'ex3', jp: 'c', en: 'c' }] }]
};

describe('targets', () => {
	test('partsOf lists the entry, then its parts in document order', () =>
		expect(partsOf('grammar', point).map((p) => [p.kind, p.id])).toEqual([
			['entry', 'te-iru'],
			['usage', 'usage1'],
			['example', 'ex1'],
			['pitfall', 'pit1'],
			['example', 'ex2'],
			['example', 'ex3']
		]));
	test('verbs: examples then common phrases', () => {
		const verb = { dict: 'たべる', examples: [{ id: 'e1' }], collocations: [{ id: 'c1' }] };
		expect(partsOf('verbs', verb).map((p) => [p.kind, p.id])).toEqual([
			['entry', 'たべる'],
			['example', 'e1'],
			['collocation', 'c1']
		]);
	});
	test('counters: things, examples, pitfalls and their examples', () => {
		const counter = { id: 'tsu', things: [{ id: 't1' }], examples: [{ id: 'e1' }], pitfalls: [{ id: 'p1', examples: [{ id: 'e2' }] }] };
		expect(partsOf('counters', counter).map((p) => p.id)).toEqual(['tsu', 't1', 'e1', 'p1', 'e2']);
	});
	test('entry ids follow the API', () => {
		expect(entryId('words', { class: 'noun', dict: 'ねこ' })).toBe('noun:ねこ');
		expect(entryId('verbs', { dict: 'いる', id: 'いる:要る' })).toBe('いる:要る');
		expect(entryId('verbs', { dict: 'たべる' })).toBe('たべる');
	});
	test('partOf finds a part by kind and id', () => {
		expect(partOf(point, 'example', 'ex2')).toEqual({ id: 'ex2', jp: 'b', en: 'b' });
		expect(partOf(point, 'entry', 'te-iru')).toBe(point);
		expect(partOf(point, 'usage', 'ex1')).toBeUndefined();
	});
	test('unknownKanjiRuns', () => {
		expect(unknownKanjiRuns('猫が毎日来る', { 毎日: 'まいにち', 来: 'く' })).toEqual(['猫']);
		expect(unknownKanjiRuns('猫と犬猫と猫', {})).toEqual(['猫', '犬猫']);
		expect(unknownKanjiRuns('ねこ', {})).toEqual([]);
	});
});

describe('entryTitle', () => {
	test('per dataset', () => {
		expect(entryTitle('verbs', { dict: 'たべる', kanji: '食べる' })).toBe('たべる (食べる)');
		expect(entryTitle('words', { dict: 'いい' })).toBe('いい');
		expect(entryTitle('counters', { counter: '本', reading: 'ほん' })).toBe('本 (ほん)');
		expect(entryTitle('grammar', { title: 'ている' })).toBe('ている');
	});
});

describe('leftBehind', () => {
	const approval = (kind: string, item_id: string) => ({ kind, item_id, reviewer_name: 'Aiko', mine: false, current: false, created_at: '' });
	const suggestion = (id: number, kind: string, item_id: string, status = 'open') =>
		({ id, kind, item_id, item_title: `title ${item_id}`, status }) as never;
	test('reviews whose target left the data, grouped by target, with the stored title', () => {
		const parts = [{ kind: 'entry', item_id: 'たべる', content_hash: 'h' }];
		const groups = leftBehind(parts, [approval('example', 'gone1'), approval('entry', 'たべる')], [
			suggestion(2, 'example', 'gone1'),
			suggestion(3, 'example', 'gone2', 'withdrawn'),
			suggestion(4, 'entry', 'たべる')
		]);
		expect(groups.map((g) => [g.kind, g.item_id, g.title, g.approvals.length, g.suggestions.length])).toEqual([
			['example', 'gone1', 'title gone1', 1, 1]
		]);
	});
	test('everything is left behind when the entry is gone', () => {
		const groups = leftBehind([], [], [suggestion(5, 'entry', 'のむ')]);
		expect(groups).toHaveLength(1);
		expect(groups[0].title).toBe('title のむ');
	});
});

describe('leftBehind and additions', () => {
	test('a pending addition is not left behind', () => {
		const add = { id: 9, action: 'add', kind: 'example', item_id: 'new001', item_title: 'x', status: 'open' } as never;
		expect(leftBehind([{ kind: 'entry', item_id: 'たべる', content_hash: 'h' }], [], [add])).toEqual([]);
	});
});

describe('addFieldsOf', () => {
	test('a new verb turns back into its form fields', () => {
		const verb = {
			type: 'u', label: 'U-verb', dict: 'はしる', kanji: '走る', meaning: 'to run', description: 'd', notes: 'n', jlpt: 'N4',
			forms: { masu_pos: 'はしります', te: 'はしって' },
			examples: [{ id: 'abcdef', form: 'te', jp: '走って行った。', en: 'Ran.' }]
		};
		expect(addFieldsOf('verbs', 'entry', verb)).toEqual({
			type: 'u', dict: 'はしる', kanji: '走る', meaning: 'to run', description: 'd', notes: 'n', jlpt: 'N4',
			masu_pos: 'はしります', te: 'はしって', example_form: 'te', example_jp: '走って行った。', example_en: 'Ran.'
		});
	});
	test('a new grammar point and a usage', () => {
		const point = { id: 'te-shimau', title: 't', summary: 's', jlpt: 'N4',
			usages: [{ id: 'u1', heading: 'h', explanation: 'e', examples: [{ id: 'e1', jp: 'j', en: 'n' }] }] };
		expect(addFieldsOf('grammar', 'entry', point)).toEqual({ id: 'te-shimau', title: 't', summary: 's', jlpt: 'N4',
			usage_heading: 'h', usage_explanation: 'e', example_jp: 'j', example_en: 'n' });
		const usage = { id: 'u2', heading: 'h', explanation: 'e', examples: [{ id: 'e2', jp: 'j', en: 'n' }] };
		expect(addFieldsOf('grammar', 'usage', usage)).toEqual({ heading: 'h', explanation: 'e', example_jp: 'j', example_en: 'n' });
	});
	test('a part keeps its own fields, without its id', () => {
		expect(addFieldsOf('verbs', 'example', { id: 'x', form: 'te', jp: 'j', en: 'n' })).toEqual({ form: 'te', jp: 'j', en: 'n' });
	});
});
