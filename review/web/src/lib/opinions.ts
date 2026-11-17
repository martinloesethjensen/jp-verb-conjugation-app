// Second opinions: the wording and rules the pages share, kept out of the components so they can be tested.
import type { Candidate, InboxSuggestion, Opinion } from './api.ts';
import { shortDate } from './dates.ts';

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

/** The candidate the Ask panel starts on: the first one; null when there is nobody to ask. */
export const firstCandidate = (candidates: Candidate[]): number | null => candidates[0]?.user ?? null;

/** The Ask button's label for the chosen person. */
export function askLabel(candidates: Candidate[], chosen: number | null): string {
	const c = candidates.find((x) => x.user === chosen);
	return c ? `Ask ${c.name}` : 'Ask';
}

/** What an answered request says: who picked which suggestion, or that neither works. */
export function answeredLine(o: Pick<Opinion, 'asked_of_name' | 'pick'>, authorOfPick: string | null): string {
	return o.pick === null ? `${o.asked_of_name} thinks neither works` : `${o.asked_of_name} picked ${authorOfPick ?? 'a'}'s suggestion`;
}

/** The muted line under a waiting request: when, where it shows up, and who else is told (the suggestions' authors). */
export function askedLine(
	o: Pick<Opinion, 'created_at' | 'asked_of_name' | 'asked_by_name'>,
	suggestions: Pick<InboxSuggestion, 'author_name' | 'status' | 'action'>[],
	now = new Date()
): string {
	const raw = o.created_at;
	const when = new Date(raw.replace(' ', 'T') + (/[zZ]|[+-]\d\d:?\d\d$/.test(raw) ? '' : 'Z'));
	const date = Number.isNaN(when.getTime()) ? '' : ` ${shortDate(when, now)}`;
	const told: string[] = [];
	for (const s of suggestions) {
		if (s.status === 'open' && s.action !== 'note' && ![o.asked_of_name, o.asked_by_name, ...told].includes(s.author_name)) told.push(s.author_name);
	}
	const who = told.length > 1 ? `${told.slice(0, -1).join(', ')} and ${told[told.length - 1]}` : told[0];
	return `Asked${date}. It shows up in their Replies.${who ? ` ${who} ${told.length > 1 ? 'are' : 'is'} told too.` : ''}`;
}

/** The index `delta` steps from `from` in a list of `length`, wrapping round (arrow keys in a radiogroup). */
export const stepIndex = (from: number, delta: number, length: number): number =>
	length === 0 ? -1 : (((from + delta) % length) + length) % length;
