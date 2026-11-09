import { readFileSync } from 'node:fs';
import { expect, test } from 'vitest';
import { render } from 'svelte/server';
import SiteHeader from './SiteHeader.svelte';
import type { Me } from './api.ts';

const admin: Me = { email: 'm@x', display_name: 'Martin', role: 'admin', public_role: 'owner', public_name: null };
const reviewer: Me = { ...admin, display_name: 'Aiko', role: 'reviewer', public_role: 'teacher' };

test('the mark has furigana and the name', () => {
	const { body } = render(SiteHeader, { props: { me: null } });
	expect(body).toContain('<ruby>添削<rt>てんさく</rt></ruby>');
	expect(body).toContain('Kotoba Table');
	expect(body).not.toContain('Sign out');
});

test('admins see Reviewers; everyone sees their initial, name and Sign out', () => {
	const a = render(SiteHeader, { props: { me: admin } }).body;
	expect(a).toContain('href="/admin"');
	expect(a).toContain('>M<');
	expect(a).toContain('href="/cdn-cgi/access/logout"');
	const r = render(SiteHeader, { props: { me: reviewer } }).body;
	expect(r).not.toContain('href="/admin"');
	expect(r).toContain('Aiko');
});

test('the phone account menu holds the same links', () => {
	const { body } = render(SiteHeader, { props: { me: admin } });
	expect(body).toMatch(/<details class="account-menu[^"]*"[\s\S]*href="\/account"[\s\S]*Sign out[\s\S]*<\/details>/);
});

test('the phone account menu closes after navigating, on Escape and on an outside tap', () => {
	const source = readFileSync(new URL('./SiteHeader.svelte', import.meta.url), 'utf8');
	expect(source).toMatch(/afterNavigate\(\s*\(\)\s*=>\s*\(?menuOpen = false/);
	expect(source).toMatch(/key === 'Escape'/);
	expect(source).toMatch(/bind:open=\{menuOpen\}/);
});

test('the brand link is a 44px target', () => {
	const source = readFileSync(new URL('./SiteHeader.svelte', import.meta.url), 'utf8');
	expect(source).toMatch(/\.name \{[^}]*min-height: 44px/);
});

test('teachers and the owner get an Inbox link; reviewers do not', () => {
	const teacher: Me = { ...reviewer, display_name: 'Keiko', role: 'teacher' };
	for (const me of [admin, teacher]) {
		const { body } = render(SiteHeader, { props: { me } });
		expect(body.match(/href="\/inbox"/g)?.length, me.role).toBe(2);
	}
	expect(render(SiteHeader, { props: { me: reviewer } }).body).not.toContain('href="/inbox"');
});
