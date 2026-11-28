import { afterEach, expect, test, vi } from 'vitest';
import { hashOf, reviewMock, type ReviewContext } from './mock-review.ts';

// One verb with one example: enough to suggest, comment on and decide a change.
const example = { id: 'iyk45k', form: 'masu_pos', jp: '朝ご飯を食べます。', en: 'I eat breakfast.' };
const verb = { dict: 'たべる', kanji: '食べる', examples: [example] };
const users: ReviewContext['users'] = [
	{ email: 'aiko@example.com', display_name: 'Aiko', role: 'reviewer', public_role: 'native', public_name: null },
	{ email: 'keiko@example.com', display_name: 'Keiko', role: 'teacher', public_role: 'teacher', public_name: null },
	{ email: 'owner@example.com', display_name: 'Martin', role: 'admin', public_role: 'owner', public_name: null }
];

function mock() {
	let me = users[0];
	const review = reviewMock({
		entries: (d) => (d === 'verbs' ? [{ item_id: 'たべる', title: 'たべる (食べる)', jlpt: null, json: verb }] : []),
		isLoaded: (d) => d === 'verbs',
		readings: () => ({}),
		formIds: () => ['masu_pos'],
		generation: () => 1,
		users,
		get me() {
			return me;
		}
	});
	const as = (email: string, path: string, method = 'GET', body: Record<string, unknown> = {}) => {
		me = users.find((u) => u.email === email)!;
		const reply = review.handle(path, method, new URLSearchParams(), body);
		if (!reply) throw new Error(`no route ${method} ${path}`);
		return reply as [number, any];
	};
	return { as };
}

afterEach(() => vi.useRealTimers());

const suggest = (m: ReturnType<typeof mock>, en: string) => {
	const [status, body] = m.as('aiko@example.com', '/suggest', 'POST', {
		dataset: 'verbs', kind: 'example', id: example.id, base_hash: hashOf(example), action: 'change', edits: { en }
	});
	expect(status, JSON.stringify(body)).toBe(201);
	return body.id as number;
};

test("a declined change's reason is the decider's comment at or after the decision, as in the Worker", () => {
	vi.useFakeTimers({ now: new Date('2026-11-05T12:00:00Z') });
	const m = mock();
	const earlier = suggest(m, 'One.');
	m.as('owner@example.com', '/comment', 'POST', { suggestion_id: earlier, body: 'Why this?' });
	vi.setSystemTime(new Date('2026-11-05T13:00:00Z'));
	expect(m.as('owner@example.com', '/decide', 'POST', { id: earlier, decision: 'decline' })[0]).toBe(200);
	const withReply = suggest(m, 'Two.');
	m.as('owner@example.com', '/decide', 'POST', { id: withReply, decision: 'decline', reply: 'Too literal.' });

	const [, c] = m.as('aiko@example.com', '/contributions');
	const reason = (id: number) => c.declined.find((d: { id: number }) => d.id === id).reason;
	expect(reason(earlier)).toBeNull();
	expect(reason(withReply)).toEqual({ by_name: 'Martin', body: 'Too literal.' });
	// The comment before the decline still counts as a reply.
	expect(c.declined.find((d: { id: number }) => d.id === earlier).replies).toBe(1);
});

test('replies leave out your own comments', () => {
	const m = mock();
	const id = suggest(m, 'One.');
	m.as('aiko@example.com', '/comment', 'POST', { suggestion_id: id, body: 'Mine.' });
	m.as('owner@example.com', '/comment', 'POST', { suggestion_id: id, body: 'Theirs.' });
	const [, c] = m.as('aiko@example.com', '/contributions');
	expect(c.waiting.find((w: { id: number }) => w.id === id).replies).toBe(1);
});

test('everyone starts with one change in a seeded release, so the Release section and Live tag show', () => {
	const m = mock();
	for (const u of users) {
		const [, c] = m.as(u.email, '/contributions');
		expect(c.releases).toHaveLength(1);
		expect(c.releases[0].label).toBe('2026.11.07');
		expect(c.releases[0].loaded_at).toBe('2026-11-07T08:00:00Z');
		expect(c.releases[0].changes).toHaveLength(1);
		expect(c.counts.live).toBe(1);
		expect(c.releases[0].changes[0].before).toBeTruthy();
	}
});

test('a declined change keeps the text it was declined against', () => {
	const m = mock();
	const id = suggest(m, 'One.');
	m.as('owner@example.com', '/decide', 'POST', { id, decision: 'decline' });
	const [, c] = m.as('aiko@example.com', '/contributions');
	expect(c.declined.find((d: { id: number }) => d.id === id).before).toEqual(example);
});
