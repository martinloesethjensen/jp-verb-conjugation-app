// Rules about a queue's items, shared by Home and the queue page.
import type { QueueItem } from './api.ts';

/** A queue item's identity within its queue. */
export const keyOf = (item: QueueItem) => `${item.dataset}/${item.kind}/${item.item_id}`;

/** Done for this reviewer: approved, suggested, skipped, or no longer in the data. */
const isDone = (item: QueueItem) => item.mine !== null || item.gone;

/** The first item this reviewer hasn't acted on yet. */
export const firstUndone = (items: QueueItem[]): QueueItem | undefined => items.find((i) => !isDone(i));

export type ItemFilter = 'all' | 'todo' | 'done';

/** The queue list's filter chips: to do is what this reviewer hasn't acted on, done is the rest. */
export function filterItems(items: QueueItem[], filter: ItemFilter): QueueItem[] {
	if (filter === 'all') return items;
	return items.filter((i) => isDone(i) === (filter === 'done'));
}
