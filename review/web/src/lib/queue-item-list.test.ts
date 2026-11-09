import { expect, test } from 'vitest';
import { render } from 'svelte/server';
import QueueItemList from './QueueItemList.svelte';
import { keyOf } from './queue-items.ts';
import type { QueueItem } from './api.ts';

const item = (item_id: string, mine: QueueItem['mine'] = null, gone = false): QueueItem => ({
	dataset: 'verbs', kind: 'example', item_id, entry_id: 'たべる', title: item_id, note: '', position: 0, gone, mine
});

test('the list counts what is left to do and marks the current item', () => {
	const items = [item('a', 'approved'), item('b'), item('c')];
	const { body } = render(QueueItemList, { props: { items, currentKey: keyOf(items[1]), filter: 'all', onselect: () => {} } });
	expect(body).toMatch(/>To do 2</);
	expect(body).toMatch(/class="entry current[^"]*"[^>]*aria-current="true"/);
});

test('an all-done queue says so under To do', () => {
	const { body } = render(QueueItemList, { props: { items: [item('a', 'approved')], currentKey: undefined, filter: 'todo', onselect: () => {} } });
	expect(body).toContain('Nothing left to do in this queue.');
});
