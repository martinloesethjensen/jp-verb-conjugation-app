// Your contributions: how the page counts, words and tags what `GET /api/contributions` returns.
import { diffFields } from './diff.ts';
import type { Change, Contributions, PublicRole, Release } from './api.ts';

export type ContributionFilter = 'all' | 'live' | 'waiting' | 'declined';
export type ChangeGroup = 'release' | 'accepted' | 'waiting' | 'declined' | 'note';

const liveCount = (c: Contributions) => c.releases.reduce((n, r) => n + r.changes.length, 0);

/** The accepted changes not in a release yet, and the accepted notes, which never ship: they wait for nothing. */
export function splitAccepted(accepted: Change[]): { next: Change[]; notes: Change[] } {
	return { next: accepted.filter((c) => c.action !== 'note'), notes: accepted.filter((c) => c.action === 'note') };
}

/** What each filter chip counts. "Waiting" holds the accepted changes that aren't in a release yet; accepted
 * notes count only in All. */
export function filterCounts(c: Contributions): Record<ContributionFilter, number> {
	const live = liveCount(c);
	const { next, notes } = splitAccepted(c.accepted);
	const waiting = next.length + c.waiting.length;
	return { all: live + waiting + c.declined.length + notes.length, live, waiting, declined: c.declined.length };
}

/** The four counts at the top. Green only for what is live in the app, and only once there is some. */
export const countTiles = (n: Contributions['counts']) => [
	{ label: 'items approved', n: n.approved, good: false },
	{ label: 'changes suggested', n: n.suggested, good: false },
	{ label: 'accepted', n: n.accepted, good: false },
	{ label: 'live in the app', n: n.live, good: n.live > 0 }
];

export function headline(c: Contributions): string {
	const n = c.counts.live;
	if (n === 0) return 'None of your changes are in the app yet.';
	return `${n} of your changes ${n === 1 ? 'is' : 'are'} in the app.`;
}

/** "7 November · 2 of your changes"; the "Earlier releases" row has no date. */
export function releaseLine(r: Release, dateFormat: (iso: string) => string): string {
	const n = `${r.changes.length} of your changes`;
	return r.loaded_at ? `${dateFormat(r.loaded_at)} · ${n}` : n;
}

export type Tag = { text: string; tone: 'live' | 'next' | 'wait' | 'no' | 'note' };

export function tagFor(change: Change, group: ChangeGroup): Tag {
	if (group === 'release') return { text: 'Live in the app', tone: 'live' };
	if (group === 'accepted') return { text: 'Next release', tone: 'next' };
	if (group === 'note') return { text: 'Accepted', tone: 'note' };
	if (group === 'waiting') return { text: 'Waiting', tone: 'wait' };
	return { text: 'Declined', tone: 'no' };
}

/** "7 November", in the viewer's own time zone. */
export const longDate = (iso: string) =>
	new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'long' });

/** The role pill in the credit panel. */
export const ROLE_PILL: Record<PublicRole, string> = { owner: 'Owner', teacher: 'Teacher', native: 'Native speaker' };

/** The strings among a change's fields, which are the ones the page can show. */
export function textFields(fields: Record<string, unknown> | null | undefined): Record<string, string> {
	return Object.fromEntries(Object.entries(fields ?? {}).filter((e): e is [string, string] => typeof e[1] === 'string'));
}

/** An id field: never shown, it means nothing to a reviewer. */
const isId = (name: string) => name === 'id' || name.endsWith('_id');

/** The fields that differ between `before` and `after`, as the red pen compares them. */
export const changedNames = (before: Record<string, unknown>, after: Record<string, string>) =>
	diffFields(before, after, Object.keys(after).filter((n) => !isId(n))).map((f) => f.name);

/** Every field to show when there is no before to compare with. */
export const plainNames = (after: Record<string, string>) => Object.keys(after).filter((n) => !isId(n));
