import { readFileSync } from 'node:fs';
import { expect, test } from 'vitest';
import { render } from 'svelte/server';
import ReviewBar from './ReviewBar.svelte';
import type { EntryReview } from './review.svelte.ts';

const stub = (approved: boolean) =>
	({ approvalsOf: () => [], suggestionsOf: () => [], approvedByMe: () => approved, hashOf: () => 'h', isJustApproved: () => false }) as unknown as EntryReview;
const props = { kind: 'example', id: 'x', value: {}, fields: [], readings: {}, forms: {} };

test('before approving, Looks right is the primary pill with a check icon', () => {
	const { body } = render(ReviewBar, { props: { ...props, review: stub(false) } });
	expect(body).toMatch(/<button[^>]*class="primary[^"]*"[^>]*>[\s\S]*?<svg[^>]*aria-hidden="true"[\s\S]*?Looks right/);
});

test('in a queue, an approved item offers Next item and Undo', () => {
	const { body } = render(ReviewBar, { props: { ...props, review: stub(true), onnext: () => {} } });
	expect(body).toMatch(/class="primary[^"]*"[^>]*>[\s\S]*?Next item/);
	expect(body).toContain('You approved this.');
	expect(body).toMatch(/>Undo</);
	expect(body).not.toContain('Looks right');
});

test('outside a queue, approved stays as it was', () => {
	const { body } = render(ReviewBar, { props: { ...props, review: stub(true) } });
	expect(body).toContain('Approved');
	expect(body).not.toContain('Next item');
});

const field = (name: string) => ({ name, input: 'text' as const, optional: false, choices: [] });

test('docked on a phone: Looks right, Suggest a change and More in the action bar', () => {
	const { body } = render(ReviewBar, {
		props: { ...props, review: stub(false), docked: true, phone: true, fields: [field('en')], onskip: async () => {} }
	});
	expect(body).toMatch(/class="action-bar[^"]*"[\s\S]*Looks right[\s\S]*Suggest a change[\s\S]*More/);
	expect(body).not.toMatch(/class="link[^"]*"[^>]*>Not sure, skip/);
});

test('docked on a phone after approving: Next item and Undo in the bar', () => {
	const { body } = render(ReviewBar, { props: { ...props, review: stub(true), docked: true, phone: true, onnext: () => {} } });
	expect(body).toMatch(/class="action-bar[^"]*"[\s\S]*Next item[\s\S]*Undo/);
});

test('not docked: no action bar', () => {
	const { body } = render(ReviewBar, { props: { ...props, review: stub(false), phone: true } });
	expect(body).not.toContain('action-bar');
});

test('approving and undoing tell the queue, so its list and count refresh', () => {
	const source = readFileSync(new URL('./ReviewBar.svelte', import.meta.url), 'utf8');
	expect(source).toMatch(/review\.approve\(kind, id\), onnext \? onchange : onaction/);
	expect(source.match(/review\.undo\(kind, id\), onchange\)/g)?.length).toBe(3);
});

test('the More sheet shows errors itself, and the page line hides while a sheet is open', () => {
	const source = readFileSync(new URL('./ReviewBar.svelte', import.meta.url), 'utf8');
	expect(source).toMatch(/<Sheet open=\{moreOpen\}[\s\S]*?<ErrorLine[\s\S]*?<\/Sheet>/);
	expect(source).toMatch(/\{#if !sheetOpen\}<ErrorLine message=\{failure\} \{stale\} \/>\{\/if\}/);
});
