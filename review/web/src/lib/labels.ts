// Display names for datasets and data values.
import type { Dataset, PublicRole } from './api.ts';

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
	dict: 'Dictionary form',
	class: 'Word class',
	masu_pos: 'Polite (ます)',
	masu_neg: 'Polite negative',
	masu_past: 'Polite past',
	masu_past_neg: 'Polite past negative',
	short_pos: 'Plain',
	short_neg: 'Plain negative',
	short_past: 'Plain past',
	short_past_neg: 'Plain past negative',
	example_form: 'First example: form',
	example_jp: 'First example: Japanese',
	example_en: 'First example: English',
	usage_heading: 'First usage: heading',
	usage_explanation: 'First usage: explanation',
	id: 'Id (lowercase, hyphens)',
	sound: 'Counting sound',
	symbol: 'Symbol',
	jp: 'Japanese',
	te: 'て-form',
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
export const JAPANESE_FIELDS = new Set([
	'jp', 'counter', 'reading', 'word', 'kana', 'wrong', 'kanji', 'dict', 'example_jp',
	'masu_pos', 'masu_neg', 'masu_past', 'masu_past_neg', 'te', 'short_pos', 'short_neg', 'short_past', 'short_past_neg'
]);

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

/** The add button's text per `"<dataset>/<kind>"`. */
export const ADD_LABELS: Record<string, string> = {
	'verbs/example': 'Add an example',
	'verbs/collocation': 'Add a common phrase',
	'counters/thing': 'Add a thing counted',
	'counters/example': 'Add an example',
	'counters/pitfall': 'Add a pitfall',
	'grammar/usage': 'Add a usage',
	'grammar/example': 'Add an example',
	'grammar/pitfall': 'Add a pitfall',
	'verbs/entry': 'Suggest a new verb',
	'words/entry': 'Suggest a new word',
	'counters/entry': 'Suggest a new counter',
	'grammar/entry': 'Suggest a new grammar point'
};

/** What the add forms say the site leaves to export. */
export const ADD_NOTE = 'Forms and readings that the app works out are added when Martin exports this.';

/** How a public role reads in a credit: "credited as a native speaker". */
export const CREDIT_ROLES: Record<PublicRole, string> = {
	owner: 'the owner',
	teacher: 'a teacher',
	native: 'a native speaker'
};

/** What the public repo says about someone: their public name, else their role. */
export const creditOf = (c: { public_role: PublicRole; public_name: string | null }) =>
	c.public_name ?? CREDIT_ROLES[c.public_role];

/** What a new entry is called, per dataset. */
export const ENTRY_NAMES: Record<string, string> = {
	verbs: 'verb',
	words: 'word',
	counters: 'counter',
	grammar: 'grammar point'
};

/** A suggestion's heading in the inbox and on the Export page: "Example", "New verb". */
export function groupTitle(s: { action: string; kind: string; dataset: string }): string {
	const adding = s.action === 'add';
	const name = s.kind === 'entry' && adding ? ENTRY_NAMES[s.dataset] : (KINDS[s.kind] ?? s.kind);
	return adding ? `New ${name}` : name;
}
