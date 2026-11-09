import { expect, test } from 'vitest';
import { firstUndone } from './queue-items.ts';
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
