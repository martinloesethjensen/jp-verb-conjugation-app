import { readFileSync } from 'node:fs';
import { describe, expect, test } from 'vitest';
import { render } from 'svelte/server';
import SuggestionCard from './SuggestionCard.svelte';
import type { Suggestion } from './api.ts';

const addition: Suggestion = {
	id: 1, action: 'add', dataset: 'verbs', kind: 'example', item_id: 'new001', entry_id: 'たべる',
	item_title: '食べてから寝ます。', author_name: 'Aiko', mine: false, status: 'open', base_hash: '',
	proposed: { id: 'new001', form: 'te', jp: '食べてから寝ます。', en: 'I eat, then sleep.' },
	furigana: null, dropped_blanks: 0, comment: '', admin_edit: null, created_at: '', decided_at: null,
	stale: false, gone: false, parent_kind: 'entry', parent_id: 'たべる', landed: false, comments: []
};

describe('SuggestionCard for an addition', () => {
	test('shows what is being added, not a red pen', () => {
		const { body } = render(SuggestionCard, { props: { suggestion: addition, current: null, names: ['form', 'jp', 'en'] } });
		expect(body).toContain('Aiko suggests adding this');
		expect(body).toContain('New');
		expect(body).toContain('I eat, then sleep.');
		expect(body).not.toContain('<del');
	});
	test('says when it has landed', () => {
		const { body } = render(SuggestionCard, {
			props: { suggestion: { ...addition, status: 'accepted', landed: true }, current: null, names: [] }
		});
		expect(body).toContain('Now in the data');
	});
});

describe('the restyled card and inbox', () => {
	const change: Suggestion = { ...addition, id: 2, action: 'change', author_name: 'aiko', proposed: { en: 'I eat, then I sleep.' } };

	test("the author line has the author's initial in an avatar", () => {
		const { body } = render(SuggestionCard, { props: { suggestion: change, current: { en: 'I eat, then sleep.' }, names: ['en'] } });
		expect(body).toMatch(/class="avatar[^"]*"[^>]*>A</);
		expect(body).toContain('suggests a change');
	});

	test('the inbox tabs are a segmented control and its buttons are pills', () => {
		const page = readFileSync(new URL('../routes/admin/inbox/+page.svelte', import.meta.url), 'utf8');
		expect(page).toMatch(/class="segmented"[^>]*role="group"|role="group"[^>]*class="segmented"/);
		expect(page).not.toMatch(/class="[^"]*\bsmall\b[^"]*"/);
	});

	test('the Open tab reads its count as words, not "Open1"', () => {
		// Svelte trims whitespace at the edges of an element's children, so the spaces are string expressions.
		const page = readFileSync(new URL('../routes/admin/inbox/+page.svelte', import.meta.url), 'utf8');
		expect(page).toContain(
			`<span class="open-count"><span class="visually-hidden">{', '}</span>{suggestions.length}<span class="visually-hidden">{' open'}</span></span>`
		);
	});

	test('the date goes through shortDate, which adds the year when it is not this year', () => {
		const card = readFileSync(new URL('./SuggestionCard.svelte', import.meta.url), 'utf8');
		expect(card).toContain('{shortDate(when)}');
	});
});
