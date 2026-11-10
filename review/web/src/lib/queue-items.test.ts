import { expect, test } from 'vitest';
import { filterItems, firstUndone } from './queue-items.ts';
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
