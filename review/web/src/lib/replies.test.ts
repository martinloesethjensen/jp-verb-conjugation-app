import { afterEach, describe, expect, test, vi } from 'vitest';
import { render } from 'svelte/server';
import type { Reply } from './api.ts';
import { firstNew, groupReplies, replies, replyText } from './replies.svelte.ts';
import RepliesBell from './RepliesBell.svelte';
import ReplyList from './ReplyList.svelte';
import { suggestionHref } from './targets.ts';

afterEach(() => {
	vi.unstubAllGlobals();
	replies.unread = 0;
	replies.list = [];
	replies.loaded = false;
});

function reply(over: Partial<Reply> = {}): Reply {
	return {
		suggestion_id: 7,
		what: 'comment',
		by_name: 'Ben',
		at: '2026-11-10T12:00:00.000Z',
		body: 'Looks good.',
		item_title: '食べる',
		dataset: 'verbs',
		kind: 'example',
		item_id: 'abc234',
		entry_id: 'たべる',
		action: 'change',
		parent_kind: null,
		parent_id: null,
		unread: true,
		...over
	};
}

describe('wording and grouping', () => {
	test('replyText says who did what', () => {
		expect(replyText(reply())).toBe('Ben replied');
		expect(replyText(reply({ what: 'accepted', by_name: 'Keiko' }))).toBe('Keiko accepted your suggestion');
		expect(replyText(reply({ what: 'declined', by_name: 'Keiko' }))).toBe('Keiko declined your suggestion');
	});

	test('groupReplies splits new from earlier', () => {
		const a = reply({ suggestion_id: 1 });
		const b = reply({ suggestion_id: 2, unread: false });
		expect(groupReplies([a, b])).toEqual({ fresh: [a], earlier: [b] });
	});
});

describe('the replies store', () => {
	test('a_failed_load_shows_no_count', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => Promise.reject(new Error('offline'))));
		await replies.refresh();
		expect(replies.unread).toBe(0);
		expect(replies.loaded).toBe(false);
	});

	test('reads in one tick go out as one request', async () => {
		const fetch = vi.fn(async () => new Response(JSON.stringify({ unread: 0 }), { status: 200, headers: { 'content-type': 'application/json' } }));
		vi.stubGlobal('fetch', fetch);
		replies.unread = 2;
		replies.list = [reply({ suggestion_id: 1 }), reply({ suggestion_id: 2 })];
		replies.read(1);
		replies.read(2);
		await vi.waitFor(() => expect(fetch).toHaveBeenCalledTimes(1));
		const [path, init] = fetch.mock.calls[0] as unknown as [string, RequestInit];
		expect(path).toBe('/api/replies/read');
		expect(JSON.parse(String(init.body))).toEqual({ ids: [1, 2] });
		await vi.waitFor(() => expect(replies.unread).toBe(0));
		expect(replies.list.every((r) => !r.unread)).toBe(true);
	});
});

describe('the bell and the list', () => {
	test('the bell shows a red count and says how many are new', () => {
		replies.unread = 3;
		const { body } = render(RepliesBell);
		expect(body).toMatch(/class="count[^"]*"[^>]*>3</);
		expect(body).toContain('Replies, 3 new');
		expect(body).toContain('href="/replies"');
	});

	test('no count when nothing is new', () => {
		const { body } = render(RepliesBell);
		expect(body).not.toMatch(/class="count/);
		expect(body).toContain('aria-label="Replies"');
	});

	test('a reply links to its thread and says who replied', () => {
		const r = reply();
		const { body } = render(ReplyList, { props: { replies: [r], readings: {} } });
		expect(body).toContain(`href="${suggestionHref(r).replaceAll("&", "&amp;")}"`);
		expect(body).toContain('Ben replied');
		expect(body).toContain('Looks good.');
	});
});

describe('firstNew', () => {
	const c = (mine: boolean, at: string) => ({ author_name: 'x', mine, body: 'b', created_at: at });
	test('nothing is new when the viewer is not in the thread', () => {
		expect(firstNew({ last_read: null, comments: [c(false, '2026-11-10T12:00:00.000Z')] })).toBe(-1);
	});
	test('skips your own comments and finds the first newer one', () => {
		const comments = [c(false, '2026-11-10T11:00:00.000Z'), c(true, '2026-11-10T12:30:00.000Z'), c(false, '2026-11-10T12:40:00.000Z')];
		expect(firstNew({ last_read: '2026-11-10T12:00:00.000Z', comments })).toBe(2);
		expect(firstNew({ last_read: '2026-11-10T13:00:00.000Z', comments })).toBe(-1);
	});
});

test('a refresh that started before a read does not bring the old count back', async () => {
	let answerRefresh: (r: Response) => void = () => {};
	const json = (body: unknown) => new Response(JSON.stringify(body), { status: 200, headers: { 'content-type': 'application/json' } });
	vi.stubGlobal(
		'fetch',
		vi.fn(async (path: string) =>
			path === '/api/replies' ? new Promise<Response>((r) => (answerRefresh = r)) : json({ unread: 0 })
		)
	);
	replies.unread = 1;
	replies.list = [reply({ suggestion_id: 1 })];
	const refreshing = replies.refresh();
	replies.read(1);
	await vi.waitFor(() => expect(replies.unread).toBe(0));
	answerRefresh(json({ unread: 1, replies: [reply({ suggestion_id: 1 })] }));
	await refreshing;
	expect(replies.unread).toBe(0);
	expect(replies.list[0].unread).toBe(false);
});
