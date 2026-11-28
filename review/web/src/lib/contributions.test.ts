import { expect, test } from 'vitest';
import { render } from 'svelte/server';
import type { Change, Contributions, Release } from './api.ts';
import { filterCounts, headline, releaseLine, tagFor } from './contributions.ts';
import ContributionRow from './ContributionRow.svelte';

const change = (over: Partial<Change> = {}): Change => ({
	id: 1,
	action: 'change',
	dataset: 'verbs',
	kind: 'example',
	item_id: 'abcdef',
	entry_id: 'nomu',
	parent_kind: null,
	parent_id: null,
	item_title: '飲む',
	proposed: { en: 'I drink tea.' },
	admin_edit: null,
	furigana: null,
	comment: '',
	created_at: '2026-11-01T10:00:00Z',
	decided_at: null,
	before: { en: 'I drinks tea.' },
	replies: 0,
	reason: null,
	...over
});
const some = (n: number) => Array.from({ length: n }, (_, i) => change({ id: i + 1 }));
const release = (label: string, n: number, loaded_at: string | null = '2026-11-07T08:00:00Z'): Release => ({
	label,
	loaded_at,
	changes: some(n)
});
const contributions = (over: Partial<Contributions> = {}): Contributions => ({
	counts: { approved: 7, suggested: 3, accepted: 3, live: 3 },
	credit: { name: null, role: 'teacher' },
	releases: [release('2026.11.07', 2), release('Earlier releases', 1, null)],
	accepted: [],
	waiting: some(3),
	declined: some(1),
	datasets: [],
	...over
});

test('filter counts: waiting is accepted plus waiting', () => {
	const c = contributions({ accepted: some(2), waiting: some(1), declined: some(1) });
	expect(filterCounts(c)).toEqual({ all: 7, live: 3, waiting: 3, declined: 1 });
});

test('the headline counts what is live', () => {
	const live = (n: number) => contributions({ counts: { approved: 0, suggested: n, accepted: n, live: n } });
	expect(headline(live(3))).toBe('3 of your changes are in the app.');
	expect(headline(live(1))).toBe('1 of your changes is in the app.');
	expect(headline(live(0))).toBe('None of your changes are in the app yet.');
});

test('a release line has its date, and none for Earlier releases', () => {
	const date = (iso: string) => (iso.startsWith('2026-11-07') ? '7 November' : '?');
	expect(releaseLine(release('2026.11.07', 2), date)).toBe('7 November · 2 of your changes');
	expect(releaseLine(release('Earlier releases', 2, null), date)).toBe('2 of your changes');
});

test('tags: live is the only green; a note is Accepted, not Next release', () => {
	expect(tagFor(change(), 'release')).toEqual({ text: 'Live in the app', tone: 'live' });
	expect(tagFor(change(), 'accepted')).toEqual({ text: 'Next release', tone: 'next' });
	expect(tagFor(change({ action: 'note' }), 'accepted')).toEqual({ text: 'Accepted', tone: 'next' });
	expect(tagFor(change(), 'waiting')).toEqual({ text: 'Waiting', tone: 'wait' });
	expect(tagFor(change(), 'declined')).toEqual({ text: 'Declined', tone: 'no' });
});

test('a row with a before shows the red pen; without one, the proposed fields plainly', () => {
	const pen = render(ContributionRow, { props: { change: change(), group: 'waiting', readings: {} } }).body;
	expect(pen).toMatch(/class="red-pen[ "]/);
	expect(pen).toContain('Waiting');
	const plain = render(ContributionRow, { props: { change: change({ before: null }), group: 'accepted', readings: {} } }).body;
	expect(plain).not.toContain('<del');
	expect(plain).not.toMatch(/class="red-pen[ "]/);
	expect(plain).toContain('I drink tea.');
	expect(plain).toContain('Next release');
});

test('a waiting row links its replies to the thread; a declined row shows the reason', () => {
	const w = render(ContributionRow, { props: { change: change({ replies: 2 }), group: 'waiting', readings: {} } }).body;
	expect(w).toMatch(/href="\/item\?[^"]*"[^>]*>2 replies</);
	const d = render(ContributionRow, {
		props: { change: change({ reason: { by_name: 'Keiko', body: 'Too formal.' } }), group: 'declined', readings: {} }
	}).body;
	expect(d).toContain('<strong>Keiko:</strong>');
	expect(d).toContain('Too formal.');
});
