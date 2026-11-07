// Run after `npm run build`: checks what Pages will actually serve.
import { readFileSync } from 'node:fs';
import { expect, test } from 'vitest';

const pages = [
	'index.html',
	'admin.html',
	'admin/inbox.html',
	'admin/queues.html',
	'admin/export.html',
	'account.html',
	'item.html',
	'queue.html',
	'add.html',
	'browse/verbs.html',
	'browse/words.html',
	'browse/counters.html',
	'browse/grammar.html'
];

test('every page carries a hash-based CSP and no inline escape hatch', () => {
	for (const page of pages) {
		const html = readFileSync(`build/${page}`, 'utf8');
		const csp = html.match(/<meta http-equiv="content-security-policy" content="([^"]+)"/i)?.[1];
		expect(csp, page).toBeDefined();
		expect(csp).toContain("script-src 'self' 'sha256-");
		expect(csp).not.toContain('unsafe-inline');
		expect(csp).not.toContain('unsafe-eval');
		expect(csp).toContain("connect-src 'self'");
		expect(csp).toContain("object-src 'none'");
	}
});

test('no page has an inline style attribute the CSP would block', () => {
	for (const page of pages) {
		expect(readFileSync(`build/${page}`, 'utf8'), page).not.toMatch(/\sstyle="/);
	}
});

test('_headers forbids framing', () => {
	const headers = readFileSync('build/_headers', 'utf8');
	expect(headers).toContain("frame-ancestors 'none'");
	expect(headers).toContain('X-Frame-Options: DENY');
});
