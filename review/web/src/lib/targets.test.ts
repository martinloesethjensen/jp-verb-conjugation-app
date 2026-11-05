import { describe, expect, test } from 'vitest';
import { entryId, partOf, partsOf, unknownKanjiRuns } from './targets.ts';

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
