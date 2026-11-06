// The mock's review routes: approvals, suggestions, comments, queues and the inbox, kept in memory for one
// dev-server run. Enough of review/api's rules to click through the pages; the Worker's tests are the
// real contract. Content hashes come from the loaded JSON, so reloading an edited data file makes earlier
// approvals and suggestions stale, as in production.
import { createHash } from 'node:crypto';
import { partOf, partsOf } from '../lib/targets.ts';
import type { Dataset } from '../lib/api.ts';

// The mock reads loosely typed JSON.
type Json = { [key: string]: any };
type Entry = { item_id: string; title: string; jlpt: string | null; json: Json };
type User = { email: string; display_name: string; role: 'admin' | 'reviewer' };
export type Reply = [number, unknown];

export type ReviewContext = {
	entries: (dataset: string) => Entry[];
	isLoaded: (dataset: string) => boolean;
	readings: () => Record<string, string>;
	formIds: () => string[];
	/** Changes whenever a file is (re)loaded. */
	generation: () => number;
	users: User[];
	me: User;
};

const DATASETS = ['verbs', 'words', 'counters', 'grammar'];
const STALE = 'this changed since you opened it; reload to see the new version';
const NOT_LOADED = "that isn't in the loaded data";
const DECIDED = 'this suggestion has already been decided';

// A copy of review/api/src/proposal.rs's table, for the forms. The Worker's copy is the one enforced.
const JLPT = ['N5', 'N4', 'N3', 'N2', 'N1'];
const f = (name: string, input = 'text', optional = false, choices: string[] = input === 'jlpt' ? JLPT : []) => ({
	name,
	input,
	optional,
	choices
});
const JP_EN = [f('jp'), f('en')];
const PITFALL = [f('heading'), f('explanation', 'long'), f('wrong', 'text', true)];
export const FIELDS: Record<string, ReturnType<typeof f>[]> = {
	'verbs/entry': [
		f('type', 'choice', false, ['ru', 'u', 'irr.']),
		f('label', 'choice', false, ['Ru-verb', 'U-verb', 'Irregular']),
		f('meaning'),
		f('description', 'long'),
		f('notes', 'long'),
		f('jlpt', 'jlpt'),
		f('teGroup', 'choice', true, ['ide', 'ite', 'nde', 'shite', 'tte'])
	],
	'verbs/example': [f('form', 'form'), f('jp'), f('en')],
	'verbs/collocation': JP_EN,
	'words/entry': [f('meaning'), f('jlpt', 'jlpt'), f('kanji', 'text', true)],
	'counters/entry': [f('counter'), f('reading'), f('meaning'), f('jlpt', 'jlpt')],
	'counters/thing': [f('word'), f('kana'), f('meaning'), f('fit', 'choice', false, ['primary', 'casual', 'acceptable'])],
	'counters/example': JP_EN,
	'counters/pitfall': PITFALL,
	'grammar/entry': [f('title'), f('summary', 'long'), f('jlpt', 'jlpt')],
	'grammar/usage': [f('heading'), f('explanation', 'long'), f('jlpt', 'jlpt', true)],
	'grammar/example': JP_EN,
	'grammar/pitfall': PITFALL
};

export const hashOf = (value: unknown) => createHash('sha256').update(JSON.stringify(value)).digest('hex');

type Approval = { dataset: string; kind: string; item_id: string; entry_id: string; reviewer: string; hash: string; created_at: string };
type Suggestion = {
	id: number; action: string; dataset: string; kind: string; item_id: string; entry_id: string; item_title: string;
	author: string; status: string; base_hash: string; proposed: Json | null; furigana: Json | null; dropped_blanks: number;
	comment: string; admin_edit: Json | null; created_at: string; decided_at: string | null;
};
type QueueRow = { id: number; title: string; description: string; archived: boolean };
type QueueItem = { queue_id: number; dataset: string; kind: string; item_id: string; entry_id: string; title: string; note: string; position: number };

export function reviewMock(ctx: ReviewContext) {
	const approvals: Approval[] = [];
	const suggestions: Suggestion[] = [];
	const comments: { suggestion_id: number; author: string; body: string; created_at: string }[] = [];
	const queues: QueueRow[] = [];
	const queueItems: QueueItem[] = [];
	const skips: { queue_id: number; dataset: string; kind: string; item_id: string; reviewer: string }[] = [];
	let nextId = 1;
	const now = () => new Date().toISOString();
	const nameOf = (email: string) => ctx.users.find((u) => u.email === email)?.display_name ?? '';
	const same = (a: { dataset: string; kind: string; item_id: string }, b: { dataset: string; kind: string; item_id: string }) =>
		a.dataset === b.dataset && a.kind === b.kind && a.item_id === b.item_id;

	// Hashing every part is slow; keep the list until the dataset's entries change (a reload).
	const cache = new Map<string, { source: unknown; list: ReturnType<typeof build> }>();
	function targets(dataset: string) {
		if (!ctx.isLoaded(dataset)) return [];
		const key = ctx.generation();
		const hit = cache.get(dataset);
		if (hit && hit.source === key) return hit.list;
		const list = build(dataset, ctx.entries(dataset));
		cache.set(dataset, { source: key, list });
		return list;
	}

	/** Every loaded target, with its entry, title, position and hash. */
	function build(dataset: string, entries: Entry[]) {
		return entries.flatMap((entry, index) =>
			partsOf(dataset as Dataset, entry.json).map((part, n) => ({
				dataset,
				kind: part.kind as string,
				item_id: part.id,
				entry_id: entry.item_id,
				title: part.kind === 'entry' ? entry.title : String(part.value.jp ?? part.value.heading ?? part.value.word ?? part.id),
				jlpt: (part.value.jlpt as string | undefined) ?? entry.jlpt,
				position: index * 10000 + n,
				hash: hashOf(part.value),
				value: part.value
			}))
		);
	}
	const find = (t: { dataset: string; kind: string; item_id: string }) => targets(t.dataset).find((x) => same(x, t));

	const approvalOut = (a: Approval) => ({
		kind: a.kind, item_id: a.item_id, reviewer_name: nameOf(a.reviewer), mine: a.reviewer === ctx.me.email,
		current: find(a)?.hash === a.hash, created_at: a.created_at
	});
	const suggestionOut = (s: Suggestion) => {
		const current = find(s);
		return {
			...s, author: undefined, author_name: nameOf(s.author), mine: s.author === ctx.me.email,
			stale: !!current && current.hash !== s.base_hash, gone: !current,
			comments: comments.filter((c) => c.suggestion_id === s.id).map((c) => ({ author_name: nameOf(c.author), body: c.body, created_at: c.created_at }))
		};
	};

	function queueOut(q: QueueRow) {
		const items = queueItems.filter((i) => i.queue_id === q.id).sort((a, b) => a.position - b.position).map((i) => {
			const current = find(i);
			const approved = !!current && approvals.some((a) => same(a, i) && a.reviewer === ctx.me.email && a.hash === current.hash);
			const suggested = suggestions.some((s) => same(s, i) && s.author === ctx.me.email && ['open', 'accepted'].includes(s.status));
			const skipped = skips.some((k) => k.queue_id === q.id && same(k, i) && k.reviewer === ctx.me.email);
			const mine = approved ? 'approved' : suggested ? 'suggested' : skipped ? 'skipped' : null;
			return { ...i, queue_id: undefined, gone: !current, mine };
		});
		const summary = {
			...q,
			total: items.length,
			done: items.filter((i) => i.gone || i.mine).length,
			with_suggestion: items.filter((i) => suggestions.some((s) => same(s, i) && s.status === 'open')).length
		};
		return { queue: summary, items };
	}

	function picked(body: Json) {
		const filter = body.filter ?? {};
		const lines = String(body.ids_text ?? '').split('\n').map((l) => l.trim()).filter(Boolean);
		const ids: string[] = [...(filter.ids ?? []), ...lines];
		const kinds: string[] = filter.kinds ?? [];
		const levels: string[] = filter.jlpt ?? [];
		const items = targets(String(filter.dataset ?? '')).filter(
			(t) =>
				(!kinds.length || kinds.includes(t.kind)) &&
				(!levels.length || levels.includes(t.jlpt ?? '')) &&
				(!filter.never_approved || !approvals.some((a) => same(a, t))) &&
				(!ids.length || ids.includes(t.item_id))
		);
		const unmatched = lines.filter((l) => !items.some((i) => i.item_id === l));
		return { items, unmatched, lines };
	}

	/** The proposed item: `edits` trimmed over the current one; an empty optional field is removed. */
	function proposedFrom(t: { dataset: string; kind: string }, current: Json, edits: Json): Json | string {
		const fields = FIELDS[`${t.dataset}/${t.kind}`] ?? [];
		const proposed: Json = { ...current };
		for (const [key, raw] of Object.entries(edits)) {
			const field = fields.find((x) => x.name === key);
			if (!field) return `${key} can't be changed here; leave a note for Martin instead`;
			const value = String(raw ?? '').trim();
			if (value.length > 2000) return `${key} is too long`;
			if (!value) {
				if (!field.optional) return `${key} can't be empty`;
				delete proposed[key];
			} else if (field.choices.length && !field.choices.includes(value)) {
				return `${key} must be one of: ${field.choices.join(', ')}`;
			} else proposed[key] = value;
		}
		if (JSON.stringify(proposed) === JSON.stringify(current)) return 'nothing changed';
		if (t.dataset === 'verbs' && t.kind === 'example' && proposed.form !== current.form && !ctx.formIds().includes(proposed.form)) {
			return `there is no form called ${proposed.form}`;
		}
		return proposed;
	}

	function checkFurigana(add: Json | undefined): string | undefined {
		for (const [key, value] of Object.entries(add ?? {})) {
			if (!/^[一-鿿々]+$/.test(key)) return `readings are for kanji: ${key}`;
			if (Object.hasOwn(ctx.readings(), key)) return `${key} already has a reading`;
			if (!/^[ぁ-ゟー]+$/.test(String(value))) return `a reading is written in hiragana: ${value}`;
		}
	}

	const targetOf = (body: Json) => ({ dataset: String(body.dataset ?? ''), kind: String(body.kind ?? ''), item_id: String(body.id ?? '') });

	function handle(path: string, method: string, params: URLSearchParams, body: Json): Reply | undefined {
		const admin = path.startsWith('/admin/');
		if (admin && (['/admin/inbox', '/admin/decide'].includes(path) || path.startsWith('/admin/queues'))) {
			if (ctx.me.role !== 'admin') return [403, { error: "this account can't do that" }];
		}
		const by = ctx.me.email;
		if (path === '/review' && method === 'GET') {
			const dataset = params.get('dataset') ?? '';
			const id = params.get('id') ?? '';
			if (!DATASETS.includes(dataset)) return [400, { error: 'unknown dataset' }];
			return [200, {
				parts: targets(dataset).filter((t) => t.entry_id === id).map((t) => ({ kind: t.kind, item_id: t.item_id, content_hash: t.hash })),
				approvals: approvals.filter((a) => a.dataset === dataset && a.entry_id === id).map(approvalOut),
				suggestions: suggestions.filter((s) => s.dataset === dataset && s.entry_id === id).reverse().map(suggestionOut)
			}];
		}
		if (path === '/approve' || path === '/approve/withdraw') {
			const t = targetOf(body);
			const current = find(t);
			const index = approvals.findIndex((a) => same(a, t) && a.reviewer === by);
			if (index >= 0) approvals.splice(index, 1);
			if (path === '/approve') {
				if (!current) return [404, { error: NOT_LOADED }];
				if (current.hash !== body.content_hash) return [409, { error: STALE }];
				approvals.push({ ...t, entry_id: current.entry_id, reviewer: by, hash: current.hash, created_at: now() });
			}
			const entry = current?.entry_id;
			return [200, { approvals: approvals.filter((a) => a.dataset === t.dataset && a.entry_id === entry).map(approvalOut) }];
		}
		if (path === '/suggest') {
			const t = targetOf(body);
			const current = find(t);
			if (!current) return [404, { error: NOT_LOADED }];
			if (current.hash !== body.base_hash) return [409, { error: STALE }];
			const comment = String(body.comment ?? '').trim();
			let proposed: Json | null = null;
			if (body.action === 'change') {
				const result = proposedFrom(t, current.value, body.edits ?? {});
				if (typeof result === 'string') return [400, { error: result }];
				const problem = checkFurigana(body.furigana);
				if (problem) return [400, { error: problem }];
				proposed = result;
			} else if (body.action === 'note' && !comment) return [400, { error: 'a note needs a comment' }];
			const furigana = body.furigana && Object.keys(body.furigana).length ? body.furigana : null;
			const existing = suggestions.find(
				(s) => same(s, t) && s.author === by && s.status === 'open' && s.action === body.action &&
					JSON.stringify(s.proposed) === JSON.stringify(proposed) && s.comment === comment
			);
			if (existing) return [200, suggestionOut(existing)];
			const s: Suggestion = {
				id: nextId++, action: body.action, ...t, entry_id: current.entry_id, item_title: current.title, author: by,
				status: 'open', base_hash: current.hash, proposed, furigana, dropped_blanks: 0, comment, admin_edit: null,
				created_at: now(), decided_at: null
			};
			suggestions.push(s);
			return [201, suggestionOut(s)];
		}
		const suggestion = suggestions.find((s) => s.id === Number(body.id ?? body.suggestion_id));
		if (path === '/suggest/withdraw') {
			if (!suggestion || suggestion.status !== 'open') return [409, { error: DECIDED }];
			if (suggestion.author !== by) return [403, { error: 'only the person who suggested it can withdraw it' }];
			Object.assign(suggestion, { status: 'withdrawn', decided_at: now() });
			return [200, suggestionOut(suggestion)];
		}
		if (path === '/comment') {
			if (!suggestion) return [404, { error: 'no such suggestion' }];
			const text = String(body.body ?? '').trim();
			if (!text) return [400, { error: "a comment can't be empty" }];
			comments.push({ suggestion_id: suggestion.id, author: by, body: text, created_at: now() });
			return [201, suggestionOut(suggestion)];
		}
		if (path === '/queues' || path === '/admin/queues') {
			if (method === 'GET') {
				const listed = queues.filter((q) => path === '/admin/queues' || !q.archived).reverse();
				return [200, { queues: listed.map((q) => queueOut(q).queue) }];
			}
			const title = String(body.title ?? '').trim();
			if (!title) return [400, { error: 'a queue needs a title' }];
			const { items } = picked(body);
			if (!items.length) return [400, { error: 'nothing matches' }];
			if (items.length > 500) return [400, { error: 'a queue holds at most 500 items; narrow the filter' }];
			const q = { id: nextId++, title, description: String(body.description ?? '').trim(), archived: false };
			queues.push(q);
			for (const i of items) {
				queueItems.push({ queue_id: q.id, dataset: i.dataset, kind: i.kind, item_id: i.item_id, entry_id: i.entry_id, title: i.title, note: '', position: i.position });
			}
			return [201, queueOut(q)];
		}
		if (path === '/admin/queues/preview') {
			const { items, unmatched, lines } = picked(body);
			if (lines.length > 500) return [400, { error: 'paste at most 500 ids' }];
			return [200, { count: items.length, items: items.slice(0, 50).map((i) => ({ ...i, note: '', gone: false, mine: null, value: undefined })), unmatched }];
		}
		const queue = queues.find((q) => q.id === Number(params.get('id') ?? body.queue_id ?? body.id));
		if (path === '/queue' || path.startsWith('/queue/') || path.startsWith('/admin/queues/')) {
			if (!queue || (queue.archived && ctx.me.role !== 'admin')) return [404, { error: 'no such queue' }];
			if (path === '/admin/queues/update') Object.assign(queue, { title: String(body.title).trim(), description: String(body.description ?? ''), archived: !!body.archived });
			const t = targetOf(body);
			const item = queueItems.find((i) => i.queue_id === queue.id && same(i, t));
			if (['/queue/skip', '/admin/queues/note', '/admin/queues/remove'].includes(path) && !item) {
				return [404, { error: "that isn't in this queue" }];
			}
			if (path === '/queue/skip') skips.push({ queue_id: queue.id, ...t, reviewer: by });
			if (path === '/admin/queues/note' && item) item.note = String(body.note ?? '').trim();
			if (path === '/admin/queues/remove' && item) queueItems.splice(queueItems.indexOf(item), 1);
			return [200, queueOut(queue)];
		}
		if (path === '/admin/inbox') {
			const status = params.get('status') ?? 'open';
			return [200, {
				suggestions: suggestions.filter((s) => s.status === status).map((s) => {
					const current = find(s);
					return { ...suggestionOut(s), current: current ? (s.kind === 'entry' ? current.value : partOf(current.value, s.kind, s.item_id) ?? current.value) : null };
				})
			}];
		}
		if (path === '/admin/decide') {
			if (!suggestion) return [404, { error: 'no such suggestion' }];
			if (suggestion.status !== 'open') return [409, { error: DECIDED }];
			const out = suggestionOut(suggestion);
			let warning: string | undefined;
			if (body.decision === 'accept') {
				const edits = body.edits && Object.keys(body.edits).length ? body.edits : null;
				const current = find(suggestion);
				if (edits) {
					if (!current) return [404, { error: NOT_LOADED }];
					const result = proposedFrom(suggestion, current.value, edits);
					if (typeof result === 'string') return [400, { error: result }];
					suggestion.admin_edit = result;
					if (body.furigana && Object.keys(body.furigana).length) suggestion.furigana = body.furigana;
				} else if (suggestion.action === 'change' && out.stale) {
					return [409, { error: 'the data changed since this was suggested; use Edit then accept' }];
				}
				if (suggestion.action === 'delete' && suggestion.kind === 'entry' && ['verbs', 'words'].includes(suggestion.dataset)) {
					warning = `Saved favourites, quiz history and widgets that point at ${suggestion.item_title} will be dropped when this is exported.`;
					if (!body.confirm) return [400, { error: warning }];
				}
			}
			Object.assign(suggestion, { status: body.decision === 'accept' ? 'accepted' : 'declined', decided_at: now() });
			const reply = String(body.reply ?? '').trim();
			if (reply) comments.push({ suggestion_id: suggestion.id, author: by, body: reply, created_at: now() });
			return [200, { ...suggestionOut(suggestion), warning }];
		}
		return undefined;
	}

	/** `(approved targets, open suggestions)` for a browse row. */
	function counts(dataset: string, entryId: string) {
		const own = targets(dataset).filter((t) => t.entry_id === entryId);
		return {
			approved: own.filter((t) => approvals.some((a) => same(a, t) && a.hash === t.hash)).length,
			open: suggestions.filter((s) => s.dataset === dataset && s.entry_id === entryId && s.status === 'open').length,
			hash: own[0]?.hash ?? 'mock'
		};
	}

	return { handle, counts };
}
