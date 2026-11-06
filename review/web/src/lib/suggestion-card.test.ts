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
