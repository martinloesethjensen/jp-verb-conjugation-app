// A stand-in for review/api during `vite dev` and `vite preview` (the built site, with its CSP), so the site
// can be worked on without Cloudflare. It runs in the local dev server only; nothing here is in the build.
// `MOCK_ROLE=reviewer npm run dev` signs you in as a reviewer instead of the owner.
import type { IncomingMessage, ServerResponse } from 'node:http';
import type { Plugin } from 'vite';

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

function handler() {
	const users: User[] = [
		{ email: 'aiko@example.com', display_name: 'Aiko', role: 'reviewer', active: true },
		{ email: 'owner@example.com', display_name: 'Martin', role: 'admin', active: true }
	];
	const me = process.env.MOCK_ROLE === 'reviewer' ? users[0] : users[1];

	return async (req: IncomingMessage, res: ServerResponse) => {
		const send = (status: number, body: unknown) => {
			res.statusCode = status;
			res.setHeader('content-type', 'application/json');
			res.end(JSON.stringify(body));
		};
		const path = req.url?.split('?')[0];
		if (path === '/me' && req.method === 'GET') {
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
