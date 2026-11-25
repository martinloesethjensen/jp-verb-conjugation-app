// Second opinions: the wording and rules the pages share, kept out of the components so they can be tested.
import { problem, type Candidate, type InboxSuggestion, type Opinion } from './api.ts';
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
	if (o.pick === null) return `${o.asked_of_name} thinks neither works`;
	return authorOfPick ? `${o.asked_of_name} picked ${authorOfPick}'s suggestion` : `${o.asked_of_name} picked a suggestion`;
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

/** The pick list's value for "Neither". */
export const NEITHER = 'neither';

/** The Ask panel's lead: what the person asked will see, for one open suggestion or several. */
export const askLead = (count: number): string =>
	count === 1
		? 'They see the suggestion and say whether it works. You still decide.'
		: 'They see both suggestions and pick one, or say why neither works. You still decide.';

/** What the asked person sees: the form to answer, the "already decided" line, or only the status line. */
export function cardMode(o: Pick<Opinion, 'mine_to_answer' | 'waiting' | 'answered_at' | 'cancelled_at'>): 'answer' | 'decided' | 'status' | 'none' {
	if (o.cancelled_at) return 'none';
	if (o.mine_to_answer && o.waiting) return 'answer';
	if (o.mine_to_answer && !o.answered_at) return 'decided';
	return o.waiting || o.answered_at ? 'status' : 'none';
}

/** What a request is about: the item's open suggestions that change it (notes don't). */
export const openChanges = <T extends Pick<InboxSuggestion, 'status' | 'action'>>(suggestions: T[]): T[] =>
	suggestions.filter((s) => s.status === 'open' && s.action !== 'note');

/** The suggestions the asked person chooses between: the open changes, less any they wrote themselves. */
export const pickable = <T extends Pick<InboxSuggestion, 'status' | 'action' | 'mine'>>(suggestions: T[]): T[] =>
	openChanges(suggestions).filter((s) => !s.mine);

/** Sends an answer, then reloads; the message to show, or null. A failed reload after a sent answer says the
 * answer went through, so nobody sends it twice. */
export async function sendAnswer(send: () => Promise<unknown>, reload: () => Promise<void> | void): Promise<string | null> {
	try {
		await send();
	} catch (e) {
		return problem(e);
	}
	try {
		await reload();
	} catch {
		return 'Your answer was sent; reload the page to see it.';
	}
	return null;
}

/** Whether Send is enabled: a suggestion picked, or "Neither" with a reason. */
export function canAnswer(pick: number | typeof NEITHER | null, body: string): boolean {
	if (pick === null) return false;
	return pick !== NEITHER || body.trim().length > 0;
}
