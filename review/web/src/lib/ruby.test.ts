import { describe, expect, test } from 'vitest';
import { segments } from './ruby.ts';

// The dictionary from Packages/VerbKit/Tests/VerbKitTests/FuriganaDictionaryTests.swift, so the
// site's ruby matches the app's (FuriganaDictionary.units(for:), minus the line-break chunking).
const R = {
	食: 'た', 日本語: 'にほんご', 来: 'く', 来ら: 'こ', 来た: 'き', 今日: 'きょう', 今夜: 'こんや', 何: 'なに',
	毎日: 'まいにち', 学校: 'がっこう', 買: 'か', 昨日: 'きのう', 行: 'い', 遅: 'おそ', 遅れ: 'おく', 三: 'さん'
};
const ruby = (text: string, reading: string) => ({ text, reading });
const plain = (text: string) => ({ text });

describe('segments', () => {
	test('empty text', () => expect(segments('', R)).toEqual([]));
	test('kana only is one segment', () => expect(segments('ありがとうございます', R)).toEqual([plain('ありがとうございます')]));
	test('a kanji gets its reading and okurigana stay plain', () =>
		expect(segments('食べる', R)).toEqual([ruby('食', 'た'), plain('べる')]));
	test('kana after the kanji choose the reading', () => {
		expect(segments('来る', R)).toEqual([ruby('来', 'く'), plain('る')]);
		expect(segments('来られる', R)).toEqual([ruby('来', 'こ'), plain('られる')]);
		expect(segments('来た', R)).toEqual([ruby('来', 'き'), plain('た')]);
	});
	test('the longest key wins', () => {
		expect(segments('遅れた', R)).toEqual([ruby('遅', 'おく'), plain('れた')]);
		expect(segments('遅い', R)).toEqual([ruby('遅', 'おそ'), plain('い')]);
	});
	test('a compound is read as one unit', () =>
		expect(segments('日本語が', R)).toEqual([ruby('日本語', 'にほんご'), plain('が')]));
	test('words written back to back split at their boundaries', () => {
		expect(segments('毎日学校', R)).toEqual([ruby('毎日', 'まいにち'), ruby('学校', 'がっこう')]);
		expect(segments('昨日買った', R)).toEqual([ruby('昨日', 'きのう'), ruby('買', 'か'), plain('った')]);
		expect(segments('今夜何', R)).toEqual([ruby('今夜', 'こんや'), ruby('何', 'なに')]);
	});
	test('an unknown kanji stays plain and does not stop the rest', () =>
		expect(segments('猫が食べる', R)).toEqual([plain('猫が'), ruby('食', 'た'), plain('べる')]));
	test('punctuation and English stay plain', () =>
		expect(segments('Drop the 食 now。', R)).toEqual([plain('Drop the '), ruby('食', 'た'), plain(' now。')]));
	test("an example's own readings win over the dictionary", () =>
		expect(segments('食べる', R, { 食: 'く' })).toEqual([ruby('食', 'く'), plain('べる')]));
	test('kana inside an extra key select its reading, like any key', () =>
		// As in the app: the reading covers the kanji part only (何); the kana pick the reading.
		expect(segments('何かありますか', R, { 何か: 'なん' })).toEqual([ruby('何', 'なん'), plain('かありますか')]));
	test('only hiragana after the kanji select a reading (何か月 keeps its kanji reading on 何)', () =>
		// A counter example's whole-run key (何か月 → なんかげつ) is for the data check, not display.
		expect(segments('何か月', { 何: 'なに', 月: 'げつ' }, { 何か月: 'なんかげつ', 何か: 'なん' })).toEqual([
			ruby('何', 'なん'),
			plain('か'),
			ruby('月', 'げつ')
		]));
	test('the iteration mark counts as kanji', () =>
		expect(segments('時々', { 時々: 'ときどき' })).toEqual([ruby('時々', 'ときどき')]));
});
