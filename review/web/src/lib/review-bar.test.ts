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
