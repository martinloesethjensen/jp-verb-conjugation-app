import type { ReadyEntry } from './api.ts';

// The ids a review-pull wrote, read from the last line of its PR summary
// ("Site suggestion ids: 12, 13. Stamp ids: none."), so the owner marks exactly those as exported.

const list = (text: string | undefined) =>
	!text || text.trim() === 'none'
		? []
		: text
				.split(',')
				.map((n) => Number(n.trim()))
				.filter((n) => Number.isInteger(n) && n > 0);

export function idsFromSummary(text: string): { suggestions: number[]; stamps: number[] } {
	const match = /Site suggestion ids: ([^.]*)\. Stamp ids: ([^.]*)\./.exec(text);
	return { suggestions: list(match?.[1]), stamps: list(match?.[2]) };
}

/** What the data pipeline stamps: entries of four datasets, and verb examples (the Worker's `stampable`). */
export function canStamp(dataset: string, kind: string): boolean {
	if (kind === 'entry') return ['counters', 'grammar', 'verbs', 'words'].includes(dataset);
	return kind === 'example' && dataset === 'verbs';
}

export type ReadyGroup = { key: string; title: string; entry: ReadyEntry | null; examples: ReadyEntry[] };

/** The ready list as rows: an entry with its ready examples under it, in the server's order. Examples whose
 * verb isn't ready themselves get a group titled by the verb. */
export function groupReady(entries: ReadyEntry[]): ReadyGroup[] {
	const groups = new Map<string, ReadyGroup>();
	for (const e of entries) {
		const key = `${e.dataset}/${e.entry_id}`;
		let group = groups.get(key);
		if (!group) {
			group = { key, title: e.entry_title, entry: null, examples: [] };
			groups.set(key, group);
		}
		if (e.kind === 'entry') group.entry = e;
		else group.examples.push(e);
	}
	return [...groups.values()];
}
