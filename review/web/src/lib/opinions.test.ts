import { describe, expect, test } from 'vitest';
import type { Candidate, InboxSuggestion, Opinion } from './api.ts';
import { inboxSuggestion } from './fixtures.ts';
import { disagreement, seenNote, stepIndex, waitingLine } from './opinions.ts';

const by = (name: string, over: Partial<InboxSuggestion> = {}): InboxSuggestion => ({
	...inboxSuggestion,
	action: 'change',
	author_name: name,
	...over
});

describe('disagreement', () => {
	test('one open change is no disagreement', () => {
		expect(disagreement([by('Kenji')])).toBeNull();
		expect(disagreement([])).toBeNull();
	});

	test('two open changes name both people', () => {
		expect(disagreement([by('Kenji'), by('Yumi')])).toBe('Kenji and Yumi disagree. Accepting one declines the other.');
	});

	test('three or more are listed with commas', () => {
		expect(disagreement([by('A'), by('B'), by('C')])).toBe('A, B and C disagree. Accepting one declines the others.');
	});

	test('a note or an accepted suggestion does not count', () => {
		expect(disagreement([by('Kenji'), by('Yumi', { action: 'note' })])).toBeNull();
		expect(disagreement([by('Kenji'), by('Yumi', { status: 'accepted' })])).toBeNull();
	});

	test('one person with two changes does not disagree with themself', () => {
		expect(disagreement([by('Kenji'), by('Kenji')])).toBeNull();
	});
});

test('seenNote says how the candidate knows the item', () => {
	const c = (seen: Candidate['seen']): Candidate => ({ user: 1, name: 'Ben', role: 'teacher', seen });
	expect(seenNote(c(null))).toBe("hasn't seen this item");
	expect(seenNote(c('approved'))).toBe('approved it earlier');
	expect(seenNote(c('suggested'))).toBe('suggested a change');
	expect(seenNote(c('commented'))).toBe('commented');
});

test('waitingLine names who is asked', () => {
	expect(waitingLine({ asked_of_name: 'Haruka' } as Opinion)).toBe("Waiting for Haruka's opinion");
});

test('stepIndex wraps both ways', () => {
	expect(stepIndex(0, 1, 3)).toBe(1);
	expect(stepIndex(2, 1, 3)).toBe(0);
	expect(stepIndex(0, -1, 3)).toBe(2);
	expect(stepIndex(0, 1, 0)).toBe(-1);
});
