import { readFileSync } from 'node:fs';
import { expect, test } from 'vitest';
import { createRawSnippet } from 'svelte';
import { render } from 'svelte/server';
import FilterChips from './FilterChips.svelte';
import Sheet from './Sheet.svelte';

const textSnippet = (text: string) => createRawSnippet(() => ({ render: () => `<p>${text}</p>` }));

test('a sheet is a labelled dialog with its title', () => {
	const { body } = render(Sheet, { props: { open: false, title: 'Items', variant: 'bottom', onclose: () => {}, children: textSnippet('List') } });
	const match = body.match(/<dialog[^>]*class="sheet bottom[^"]*"[^>]*aria-labelledby="([^"]+)"/);
	expect(match).not.toBeNull();
	expect(body).toMatch(new RegExp(`<h2[^>]*id="${match![1]}"[^>]*>Items</h2>`));
	expect(body).toContain('<p>List</p>');
});

test('a full-screen sheet has a Cancel button', () => {
	const { body } = render(Sheet, { props: { open: false, title: 'Suggest a change', variant: 'full', onclose: () => {}, children: textSnippet('Form') } });
	expect(body).toMatch(/<button[^>]*class="link[^"]*"[^>]*>Cancel<\/button>/);
});

test('filter chips mark the chosen one and show counts', () => {
	const { body } = render(FilterChips, {
		props: { label: 'Show', value: 'todo', options: [{ value: 'all', label: 'All' }, { value: 'todo', label: 'To do', count: 22 }] }
	});
	expect(body).toMatch(/role="group"[^>]*aria-label="Show"/);
	expect(body).toMatch(/aria-pressed="true"[^>]*>To do 22</);
	expect(body).toMatch(/aria-pressed="false"[^>]*>All</);
});

test('a sheet the browser closes on its own (Android back) tells its parent', () => {
	const source = readFileSync(new URL('./Sheet.svelte', import.meta.url), 'utf8');
	expect(source).toMatch(/\bonclose=\{onDialogClose\}/);
	expect(source).toMatch(/function onDialogClose\(\)\s*\{\s*if \(open\) onclose\(\);/);
});
