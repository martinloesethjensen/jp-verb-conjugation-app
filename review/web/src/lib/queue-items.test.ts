import { expect, test } from 'vitest';
import { render } from 'svelte/server';
import { filterItems, firstUndone } from './queue-items.ts';
import ReviewBar from './ReviewBar.svelte';
import type { EntryReview } from './review.svelte.ts';
import type { QueueItem } from './api.ts';

const item = (item_id: string, mine: QueueItem['mine'] = null, gone = false): QueueItem => ({
	dataset: 'verbs', kind: 'example', item_id, entry_id: 'たべる', title: item_id, note: '', position: 0, gone, mine
});

test('firstUndone skips approved, suggested, skipped and gone items', () => {
	const items = [item('a', 'approved'), item('b', 'suggested'), item('c', 'skipped'), item('d', null, true), item('e'), item('f')];
	expect(firstUndone(items)?.item_id).toBe('e');
});

test('firstUndone is undefined when everything is done', () => {
	expect(firstUndone([item('a', 'approved'), item('b', null, true)])).toBeUndefined();
	expect(firstUndone([])).toBeUndefined();
});

test('filterItems splits a mixed list into to do and done', () => {
	const items = [item('a', 'approved'), item('b'), item('c', 'skipped'), item('d', null, true), item('e')];
	expect(filterItems(items, 'all').map((i) => i.item_id)).toEqual(['a', 'b', 'c', 'd', 'e']);
	expect(filterItems(items, 'todo').map((i) => i.item_id)).toEqual(['b', 'e']);
	expect(filterItems(items, 'done').map((i) => i.item_id)).toEqual(['a', 'c', 'd']);
});

test('filterItems on an all-done queue leaves nothing to do', () => {
	expect(filterItems([item('a', 'approved'), item('b', 'suggested')], 'todo')).toEqual([]);
});

test('Looks right is the primary pill with a check icon', () => {
	const review = { approvalsOf: () => [], suggestionsOf: () => [], approvedByMe: () => false,
		hashOf: () => 'h', isJustApproved: () => false } as unknown as EntryReview;
	const { body } = render(ReviewBar, { props: { review, kind: 'example', id: 'x', value: {}, fields: [], readings: {}, forms: {} } });
	expect(body).toMatch(/<button[^>]*class="primary[^"]*"[^>]*>[\s\S]*?<svg[^>]*aria-hidden="true"[\s\S]*?Looks right/);
});
