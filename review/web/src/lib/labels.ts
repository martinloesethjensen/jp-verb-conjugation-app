// Display names for datasets and data values.
import type { Dataset } from './api.ts';

export const DATASET_TITLES: Record<Dataset, string> = {
	verbs: 'Verbs',
	words: 'Words',
	counters: 'Counters',
	grammar: 'Grammar'
};

export const WORD_CLASSES: Record<string, string> = {
	'i-adjective': 'い-adjective',
	'na-adjective': 'な-adjective',
	noun: 'Noun'
};

export const FITS: Record<string, string> = {
	primary: 'Primary',
	casual: 'Casual',
	acceptable: 'Acceptable'
};

/** What each kind of target is called on the page. */
export const KINDS: Record<string, string> = {
	entry: 'entry',
	example: 'example',
	collocation: 'common phrase',
	usage: 'usage',
	pitfall: 'pitfall',
	thing: 'thing counted'
};

/** Plural kind names for the queue builder's checkboxes. */
export const KIND_PLURALS: Record<string, string> = {
	entry: 'Entries',
	example: 'Examples',
	collocation: 'Common phrases',
	usage: 'Usages',
	pitfall: 'Pitfalls',
	thing: 'Things counted'
};

/** The kinds each dataset has. */
export const DATASET_KINDS: Record<Dataset, string[]> = {
	verbs: ['entry', 'example', 'collocation'],
	words: ['entry'],
	counters: ['entry', 'thing', 'example', 'pitfall'],
	grammar: ['entry', 'usage', 'example', 'pitfall']
};

const FIELD_LABELS: Record<string, string> = {
	jp: 'Japanese',
	en: 'English',
	type: 'Verb type',
	label: 'Verb group',
	teGroup: 'て-form group',
	jlpt: 'JLPT level',
	counter: 'Counter',
	reading: 'Reading',
	word: 'Word',
	kana: 'Kana',
	fit: 'How well it fits',
	wrong: 'Wrong version',
	kanji: 'Kanji'
};

/** A field's label: "Japanese" for `jp`, otherwise the name in sentence case. */
export function fieldLabel(name: string): string {
	return FIELD_LABELS[name] ?? name.charAt(0).toUpperCase() + name.slice(1);
}

/** Fields holding Japanese text, shown in Mincho and checked for unknown kanji. */
export const JAPANESE_FIELDS = new Set(['jp', 'counter', 'reading', 'word', 'kana', 'wrong', 'kanji']);

const CHOICE_LABELS: Record<string, Record<string, string>> = {
	type: { ru: 'ru', u: 'u', 'irr.': 'irregular' },
	label: { 'Ru-verb': 'Ru-verb', 'U-verb': 'U-verb', Irregular: 'Irregular' },
	teGroup: { ide: 'いで', ite: 'いて', nde: 'んで', shite: 'して', tte: 'って' },
	fit: FITS
};

/** The label for one choice of a choice field. */
export function choiceLabel(field: string, value: string): string {
	return CHOICE_LABELS[field]?.[value] ?? value;
}
