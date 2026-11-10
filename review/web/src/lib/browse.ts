// The browse list's filter: a JLPT level, then a case-insensitive search of the title and subtitle.
import type { ItemSummary } from './api.ts';

export function browseFilter(items: ItemSummary[], search: string, level: string): ItemSummary[] {
	const needle = search.trim().toLowerCase();
	return items.filter(
		(item) =>
			(!level || item.jlpt === level) && (!needle || `${item.title} ${item.subtitle}`.toLowerCase().includes(needle))
	);
}
