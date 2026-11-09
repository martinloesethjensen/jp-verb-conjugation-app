import { expect, test } from 'vitest';
import { render } from 'svelte/server';
import InboxGroupHeader from './InboxGroupHeader.svelte';
import { inboxSuggestion } from './fixtures.ts';

test('the group header shows the item as it is now, with furigana', () => {
	const first = { ...inboxSuggestion, action: 'change' as const, current: { id: 'e1', form: 'masu_past', jp: '食べました。', en: 'I ate.' } };
	const { body } = render(InboxGroupHeader, { props: { first, count: 2, readings: { 食: 'た' }, forms: {} } });
	expect(body).toContain('2 suggestions');
	expect(body).toMatch(/class="now[^"]*"[\s\S]*<ruby[^>]*>食<rt>た<\/rt><\/ruby>/);
});

test('no current item: no well', () => {
	const { body } = render(InboxGroupHeader, { props: { first: { ...inboxSuggestion, current: null }, count: 1, readings: {}, forms: {} } });
	expect(body).toContain('1 suggestion');
	expect(body).not.toContain('class="now');
});
