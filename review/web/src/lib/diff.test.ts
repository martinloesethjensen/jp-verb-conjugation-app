import { describe, expect, test } from 'vitest';
import { diffFields, diffText } from './diff.ts';

describe('diffText', () => {
	test('a changed particle', () =>
		expect(diffText('毎日学校に行きます', '毎日学校へ行きます')).toEqual([
			{ same: '毎日学校' },
			{ removed: 'に' },
			{ added: 'へ' },
			{ same: '行きます' }
		]));
	test('identical text is one piece', () => expect(diffText('同じ', '同じ')).toEqual([{ same: '同じ' }]));
	test('all new', () => expect(diffText('', 'あ')).toEqual([{ added: 'あ' }]));
	test('all gone', () => expect(diffText('あい', '')).toEqual([{ removed: 'あい' }]));
	test('code points, not UTF-16 units', () =>
		expect(diffText('𠮷野', '𠮷田')).toEqual([{ same: '𠮷' }, { removed: '野' }, { added: '田' }]));
});

describe('diffFields', () => {
	test('only changed fields are listed', () =>
		expect(diffFields({ jp: 'a', en: 'b' }, { jp: 'a', en: 'c' }, ['jp', 'en'])).toEqual([
			{ name: 'en', pieces: [{ removed: 'b' }, { added: 'c' }] }
		]));
	test('a removed optional field and an added one', () =>
		expect(diffFields({ wrong: 'x' }, { kanji: '猫' }, ['wrong', 'kanji'])).toEqual([
			{ name: 'wrong', pieces: [{ removed: 'x' }] },
			{ name: 'kanji', pieces: [{ added: '猫' }] }
		]));
});
