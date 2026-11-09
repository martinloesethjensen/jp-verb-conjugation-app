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
