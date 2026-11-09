import { readFileSync } from 'node:fs';
import { expect, test } from 'vitest';
import { render } from 'svelte/server';
import HomeView from './HomeView.svelte';
import QueueStack from './QueueStack.svelte';
import type { QueueSummary } from './api.ts';

const q = (id: number, done: number, total: number): QueueSummary =>
	({ id, title: `Queue ${id}`, description: '', total, done, with_suggestion: 0, archived: false });

test('greets by name and features the first unfinished queue', () => {
	const { body } = render(HomeView, { props: { name: 'Aiko', queues: [q(1, 40, 40), q(2, 18, 40)], files: [], next: undefined, readings: {} } });
	expect(body).toContain('Hello, Aiko.');
	expect(body).toMatch(/class="stack featured[^"]*"[^>]*href="\/queue\?id=2"/);
	expect(body).toContain('Continue reviewing');
});

test('the lead counts queues in the singular and plural', () => {
	const one = render(HomeView, { props: { name: 'Aiko', queues: [q(1, 0, 4)], files: [], next: undefined, readings: {} } }).body;
	expect(one).toContain('Martin has 1 queue for you.');
	const two = render(HomeView, { props: { name: 'Aiko', queues: [q(1, 0, 4), q(2, 0, 4)], files: [], next: undefined, readings: {} } }).body;
	expect(two).toContain('Martin has 2 queues for you.');
});

test('a finished queue carries the seal', () => {
	const { body } = render(QueueStack, { props: { queue: q(1, 40, 40), featured: false } });
	expect(body).toContain('All done, thank you');
	expect(body).toContain('<ruby>確認<rt>かくにん</rt></ruby>');
});

test('no queues: the empty card', () => {
	const { body } = render(HomeView, { props: { name: 'Aiko', queues: [], files: [], next: undefined, readings: {} } });
	expect(body).toContain('Hello, Aiko.');
	expect(body).toContain('Nothing is waiting for you yet.');
});

test('browse cards have Japanese labels with furigana, and survive a failed snapshot', () => {
	const { body } = render(HomeView, { props: { name: 'Aiko', queues: [], files: [], next: undefined, readings: {} } });
	expect(body).toContain('<ruby>助数詞<rt>じょすうし</rt></ruby>');
	expect(body.match(/Not loaded yet/g)).toHaveLength(4);
});

test('the Continue card previews the next item with furigana', () => {
	const next = { dataset: 'verbs', kind: 'entry', item_id: 'taberu', entry_id: 'taberu', title: '食べる', note: '', position: 0, gone: false, mine: null };
	const { body } = render(HomeView, { props: { name: 'Aiko', queues: [q(2, 18, 40)], files: [], next, readings: { 食: 'た' } } });
	expect(body).toContain('Next up');
	expect(body).toMatch(/<ruby[^>]*>食<rt>た<\/rt><\/ruby>/);
});

test('a long unbroken name wraps instead of widening the page', () => {
	const source = readFileSync(new URL('./HomeView.svelte', import.meta.url), 'utf8');
	expect(source).toMatch(/\.intro h1 \{[^}]*overflow-wrap: anywhere/);
	const card = readFileSync(new URL('./SuggestionCard.svelte', import.meta.url), 'utf8');
	expect(card).toMatch(/\.who \{[^}]*overflow-wrap: anywhere/);
});
