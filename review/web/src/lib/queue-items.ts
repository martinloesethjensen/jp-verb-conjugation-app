// Rules about a queue's items, shared by Home and the queue page.
import type { QueueItem } from './api.ts';

/** Done for this reviewer: approved, suggested, skipped, or no longer in the data. */
const isDone = (item: QueueItem) => item.mine !== null || item.gone;

/** The first item this reviewer hasn't acted on yet. */
export const firstUndone = (items: QueueItem[]): QueueItem | undefined => items.find((i) => !isDone(i));
