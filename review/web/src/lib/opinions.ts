// Second opinions: the wording and rules the pages share, kept out of the components so they can be tested.
import type { Candidate, InboxSuggestion, Opinion } from './api.ts';

/** The banner over an item's open changes when several people want it changed differently; null when there
 * is nothing to disagree about. Notes don't count: they don't change the item. */
export function disagreement(items: InboxSuggestion[]): string | null {
	const names: string[] = [];
	for (const s of items) {
		if (s.status === 'open' && s.action !== 'note' && !names.includes(s.author_name)) names.push(s.author_name);
	}
	if (names.length < 2) return null;
	const who = `${names.slice(0, -1).join(', ')} and ${names[names.length - 1]}`;
	return `${who} disagree. Accepting one declines the ${names.length === 2 ? 'other' : 'others'}.`;
}

/** What the asker is told about a candidate: whether they have looked at the item. */
export function seenNote(c: Candidate): string {
	if (c.seen === 'approved') return 'approved it earlier';
	if (c.seen === 'suggested') return 'suggested a change';
	if (c.seen === 'commented') return 'commented';
	return "hasn't seen this item";
}

/** The line on an item that is waiting for someone's answer. */
export function waitingLine(o: Pick<Opinion, 'asked_of_name'>): string {
	return `Waiting for ${o.asked_of_name}'s opinion`;
}
