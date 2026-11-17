import { expect, test } from 'vitest';
import { render } from 'svelte/server';
import AskOpinion from './AskOpinion.svelte';
import OpinionStatus from './OpinionStatus.svelte';
import { answeredLine, askedLine, askLabel, firstCandidate } from './opinions.ts';
import { inboxSuggestion } from './fixtures.ts';
import type { Candidate, Opinion } from './api.ts';

const candidates: Candidate[] = [
	{ user: 7, name: 'Yumi', role: 'teacher', seen: 'approved' },
	{ user: 9, name: 'Kenji', role: 'native', seen: null }
];
const target = { dataset: 'verbs', kind: 'example', id: 'new001' };
const opinion: Opinion = {
	id: 1, dataset: 'verbs', kind: 'example', item_id: 'new001', entry_id: 'たべる', item_title: '食べてから寝ます。', anchor_id: 1,
	asked_by_name: 'Martin', asked_of_name: 'Yumi', mine_asked: true, mine_to_answer: false, question: '', created_at: '2026-11-17 09:00:00',
	answered_at: null, pick: null, answer: '', cancelled_at: null, waiting: true
};

test('the first candidate is preselected and the button names them', () => {
	expect(firstCandidate(candidates)).toBe(7);
	expect(firstCandidate([])).toBeNull();
	expect(askLabel(candidates, 9)).toBe('Ask Kenji');
	expect(askLabel([], null)).toBe('Ask');
});

test('the panel lists the people with what they have seen, and asks the first', () => {
	const { body } = render(AskOpinion, { props: { target, onasked: () => {}, candidates } });
	expect(body).toContain('Ask for a second opinion');
	expect(body).toContain('approved it earlier');
	expect(body).toContain("hasn't seen this item");
	expect(body).toContain('Ask Yumi');
	expect(body).toMatch(/role="radio"[^>]*aria-checked="true"[\s\S]*Yumi/);
});

test('a failed ask shows the Worker message', () => {
	const { body } = render(AskOpinion, { props: { target, onasked: () => {}, candidates, error: 'Yumi has an open request already' } });
	expect(body).toContain('role="alert"');
	expect(body).toContain('Yumi has an open request already');
});

test('a waiting request says who, and only the asker may cancel', () => {
	const mine = render(OpinionStatus, { props: { opinion, suggestions: [inboxSuggestion], oncancel: () => {} } }).body;
	expect(mine).toContain("Waiting for Yumi's opinion");
	expect(mine).toContain('Cancel the request');
	const other = render(OpinionStatus, { props: { opinion: { ...opinion, mine_asked: false, asked_by_name: 'Kenji' }, suggestions: [], oncancel: () => {} } }).body;
	expect(other).not.toContain('Cancel the request');
});

test('an answer names the pick or says neither works, with the reason', () => {
	expect(answeredLine({ asked_of_name: 'Yumi', pick: 1 }, 'Aiko')).toBe("Yumi picked Aiko's suggestion");
	expect(answeredLine({ asked_of_name: 'Yumi', pick: null }, null)).toBe('Yumi thinks neither works');
	const answered = { ...opinion, waiting: false, answered_at: '2026-11-17 10:00:00', pick: 1, answer: 'The polite form fits.' };
	const { body } = render(OpinionStatus, { props: { opinion: answered, suggestions: [inboxSuggestion], oncancel: () => {} } });
	expect(body).toContain('Yumi picked Aiko');
	expect(body).toContain('The polite form fits.');
});

test('the asked line says who else is told', () => {
	const a = { author_name: 'Aiko', status: 'open', action: 'change' } as const;
	const k = { author_name: 'Kenji', status: 'open', action: 'delete' } as const;
	const line = askedLine(opinion, [a, k, { ...a, author_name: 'Yumi' }, { ...a, author_name: 'Mio', action: 'note' }], new Date('2026-11-17T12:00:00Z'));
	expect(line).toMatch(/^Asked .*17.*\. It shows up in their Replies\. Aiko and Kenji are told too\.$/);
});
