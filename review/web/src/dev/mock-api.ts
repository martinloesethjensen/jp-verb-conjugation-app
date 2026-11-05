// A stand-in for review/api during `vite dev` and `vite preview` (the built site, with its CSP), so the site
// can be worked on without Cloudflare. It runs in the local dev server only; nothing here is in the build.
// `MOCK_ROLE=reviewer npm run dev` signs you in as a reviewer instead of the owner.
import { readFileSync } from 'node:fs';
import type { IncomingMessage, ServerResponse } from 'node:http';
import type { Plugin } from 'vite';
import { FIELDS, reviewMock } from './mock-review.ts';

type User = { email: string; display_name: string; role: 'admin' | 'reviewer'; active: boolean };

export function mockApi(): Plugin {
	return {
		name: 'review-mock-api',
		configureServer(server) {
			server.middlewares.use('/api', handler());
			server.middlewares.use('/cdn-cgi/access/logout', signedOut);
		},
		configurePreviewServer(server) {
			server.middlewares.use('/api', handler());
			server.middlewares.use('/cdn-cgi/access/logout', signedOut);
		}
	};
}

// Stands in for Access's logout page, which only exists behind Cloudflare.
function signedOut(_req: IncomingMessage, res: ServerResponse) {
	res.setHeader('content-type', 'text/plain; charset=utf-8');
	res.end('Signed out (mock). In production Cloudflare Access ends the session here.');
}

// --- Published data, read from the repo's data/ at dev-server start ------------------------------

const DATA = new URL('../../../../data/', import.meta.url);
const FILES = ['furigana', 'forms', 'words', 'counters', 'grammar', 'verbs'] as const;
// The mock reads loosely typed JSON.
type Json = { [key: string]: any };

function readData(name: string): Json {
	return JSON.parse(readFileSync(new URL(`${name}.json`, DATA), 'utf8'));
}

const STABLE_ID = /^[a-km-np-z2-9]{6}$/;

/** Objects inside an entry with a stable id: its examples, usages, pitfalls, things. */
function parts(value: unknown, top = true): number {
	if (Array.isArray(value)) return value.reduce((n: number, v) => n + parts(v, false), 0);
	if (value && typeof value === 'object') {
		const own = !top && typeof (value as Json).id === 'string' && STABLE_ID.test((value as Json).id) ? 1 : 0;
		return own + Object.values(value).reduce((n: number, v) => n + parts(v, false), 0);
	}
	return 0;
}

/** The same ids and titles as review/api/src/items.rs, enough for the pages. */
function entries(dataset: string, doc: Json) {
	const dictTitle = (e: Json) => (e.kanji ? `${e.dict} (${e.kanji})` : e.dict);
	return (doc[dataset] as Json[]).map((e) => {
		const [id, title, subtitle] =
			dataset === 'verbs' ? [e.id ?? e.dict, dictTitle(e), e.meaning]
			: dataset === 'words' ? [`${e.class}:${e.dict}`, dictTitle(e), e.meaning]
			: dataset === 'counters' ? [e.id, `${e.counter} (${e.reading})`, e.meaning]
			: [e.id, e.title, e.summary];
		return { item_id: id, title, subtitle, jlpt: e.jlpt ?? null, parts: parts(e), json: e };
	});
}

function publishedData() {
	const manifest = readData('manifest');
	const docs = Object.fromEntries(FILES.map((f) => [f, readData(f)]));
	const version = (f: string) => (f === 'verbs' ? manifest.version : manifest[f].version) as string;
	const loaded = new Map<string, { name: string; version: string; sha256: string; git_ref: null; item_count: number; imported_at: string; imported_by: string }>();
	return {
		load(file: string) {
			if (!(FILES as readonly string[]).includes(file)) return undefined;
			// Re-read, so editing a data file and reloading it makes earlier reviews stale.
			docs[file] = readData(file);
			const snapshot = {
				name: file,
				version: version(file),
				sha256: 'mock',
				git_ref: null,
				item_count: ['furigana', 'forms'].includes(file) ? 0 : entries(file, docs[file]).length,
				imported_at: new Date().toISOString(),
				imported_by: 'owner@example.com'
			};
			loaded.set(file, snapshot);
			return snapshot;
		},
		files: () => FILES.filter((f) => loaded.has(f)).map((f) => loaded.get(f)),
		isLoaded: (f: string) => loaded.has(f),
		version,
		entries: (f: string) => entries(f, docs[f]),
		reference: () => ({
			readings: loaded.has('furigana') ? docs.furigana.readings : {},
			forms: loaded.has('forms')
				? Object.fromEntries((docs.forms.forms as Json[]).map((f) => [f.id, f.label]))
				: {},
			fields: FIELDS
		}),
		formIds: () => (loaded.has('forms') ? (docs.forms.forms as Json[]).map((f) => f.id as string) : [])
	};
}

function handler() {
	const users: User[] = [
		{ email: 'aiko@example.com', display_name: 'Aiko', role: 'reviewer', active: true },
		{ email: 'owner@example.com', display_name: 'Martin', role: 'admin', active: true }
	];
	const me = process.env.MOCK_ROLE === 'reviewer' ? users[0] : users[1];
	const data = publishedData();
	if (process.env.MOCK_LOADED) for (const f of FILES) data.load(f);
	const review = reviewMock({
		entries: data.entries,
		isLoaded: data.isLoaded,
		readings: () => data.reference().readings,
		formIds: data.formIds,
		users,
		me
	});

	return async (req: IncomingMessage, res: ServerResponse) => {
		const send = (status: number, body: unknown) => {
			res.statusCode = status;
			res.setHeader('content-type', 'application/json');
			res.end(JSON.stringify(body));
		};
		const [path, query = ''] = (req.url ?? '').split('?');
		const params = new URLSearchParams(query);
		const browsable = ['verbs', 'words', 'counters', 'grammar'];
		if (path === '/snapshot' && req.method === 'GET') return send(200, { files: data.files() });
		if (path === '/reference' && req.method === 'GET') return send(200, data.reference());
		if ((path === '/items' || path === '/item') && req.method === 'GET') {
			const dataset = params.get('dataset') ?? '';
			if (!browsable.includes(dataset)) return send(400, { error: 'unknown dataset' });
			if (!data.isLoaded(dataset)) return send(404, { error: "Martin hasn't loaded this data yet." });
			const all = data.entries(dataset);
			if (path === '/items') {
				const items = all.map((e) => {
					const { approved, open } = review.counts(dataset, e.item_id);
					return { item_id: e.item_id, title: e.title, subtitle: e.subtitle, jlpt: e.jlpt, parts: e.parts, approved, open, targets: e.parts + 1 };
				});
				return send(200, { dataset, version: data.version(dataset), items });
			}
			const id = params.get('id');
			if (!id) return send(400, { error: 'which item? (id is missing)' });
			const found = all.find((e) => e.item_id === id);
			if (!found) return send(404, { error: 'no such item' });
			const contentHash = review.counts(dataset, id).hash;
			return send(200, { dataset, version: data.version(dataset), id, content_hash: contentHash, item: found.json });
		}
		const reviewed = review.handle(path ?? '', req.method ?? 'GET', params, req.method === 'POST' ? await readJson(req) : {});
		if (reviewed) return send(reviewed[0], reviewed[1]);
		if (path?.startsWith('/admin/snapshot/') && req.method === 'POST') {
			if (me.role !== 'admin') return send(403, { error: "this account can't do that" });
			const body = await readJson(req);
			if (path === '/admin/snapshot/begin') {
				const file = String(body.file ?? '');
				if (!(FILES as readonly string[]).includes(file)) return send(400, { error: 'unknown data file' });
				const slices = ['furigana', 'forms'].includes(file) ? 0 : Math.ceil(data.entries(file).length / 10);
				return send(200, { load_id: `${file}-mock`, file, version: data.version(file), slices });
			}
			const file = String(body.load_id ?? '').replace(/-mock$/, '');
			if (!(FILES as readonly string[]).includes(file)) {
				return send(409, { error: 'this load is no longer running; start again' });
			}
			if (path === '/admin/snapshot/slice') return send(200, { load_id: body.load_id, slice: body.slice, rows: 10 });
			if (path === '/admin/snapshot/finish') return send(200, data.load(file));
		}
		if (path === '/me' && req.method === 'GET') {
			return send(200, { email: me.email, display_name: me.display_name, role: me.role });
		}
		if (path === '/me/name' && req.method === 'POST') {
			const name = String((await readJson(req)).display_name ?? '').trim();
			if (!name || name.length > 40) {
				return send(400, { error: 'the display name must be 1 to 40 characters' });
			}
			me.display_name = name;
			return send(200, { email: me.email, display_name: me.display_name, role: me.role });
		}
		if (path?.startsWith('/admin/')) {
			if (me.role !== 'admin') return send(403, { error: "this account can't do that" });
			if (path === '/admin/users' && req.method === 'GET') return send(200, { users });
			const body = await readJson(req);
			if (path === '/admin/users' && req.method === 'POST') {
				const email = String(body.email ?? '').trim().toLowerCase();
				if (users.some((u) => u.email === email)) {
					return send(409, { error: 'that email is already a reviewer' });
				}
				const user: User = {
					email,
					display_name: String(body.display_name ?? '').trim(),
					role: 'reviewer',
					active: true
				};
				users.push(user);
				users.sort((a, b) => a.display_name.localeCompare(b.display_name));
				return send(201, user);
			}
			if (path === '/admin/users/active' && req.method === 'POST') {
				const user = users.find((u) => u.email === body.email);
				if (!user) return send(404, { error: 'no reviewer has that email' });
				user.active = Boolean(body.active);
				return send(200, user);
			}
		}
		send(404, { error: 'no such endpoint' });
	};
}

async function readJson(req: IncomingMessage): Promise<Record<string, unknown>> {
	let text = '';
	for await (const chunk of req) text += chunk;
	try {
		return JSON.parse(text || '{}');
	} catch {
		return {};
	}
}
