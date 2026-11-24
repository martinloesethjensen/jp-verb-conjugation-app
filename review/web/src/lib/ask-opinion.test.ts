import { readFileSync } from 'node:fs';
import { expect, test } from 'vitest';
import { render } from 'svelte/server';
import AskOpinion from './AskOpinion.svelte';
import OpinionStatus from './OpinionStatus.svelte';
import { answeredLine, askedLine, askLabel, askLead, firstCandidate } from './opinions.ts';
import { roleLabel } from './labels.ts';
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
	answered_at: null, pick: null, answer: '', cancelled_at: null, closed_at: null, waiting: true
};

test('the first candidate is preselected and the button names them', () => {
	expect(firstCandidate(candidates)).toBe(7);
	expect(firstCandidate([])).toBeNull();
	expect(askLabel(candidates, 9)).toBe('Ask Kenji');
	expect(askLabel([], null)).toBe('Ask');
});

test('the panel lists the people with what they have seen, and asks the first', () => {
	const { body } = render(AskOpinion, { props: { target, onasked: () => {}, open: true, candidates } });
	expect(body).toContain('Ask for a second opinion');
	expect(body).toContain('approved it earlier');
	expect(body).toContain("hasn't seen this item");
	expect(body).toContain('Ask Yumi');
	expect(body).toMatch(/role="radio"[^>]*aria-checked="true"[\s\S]*Yumi/);
});

test('a failed ask shows the Worker message', () => {
	const { body } = render(AskOpinion, { props: { target, onasked: () => {}, open: true, candidates, error: 'Yumi has an open request already' } });
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

test('the radiogroup has one tab stop: the chosen person', () => {
	const { body } = render(AskOpinion, { props: { target, onasked: () => {}, open: true, candidates } });
	expect(body.match(/role="radio"[^>]*tabindex="0"/g)).toHaveLength(1);
	expect(body.match(/role="radio"[^>]*tabindex="-1"/g)).toHaveLength(1);
});

test('a pick that is not in the group still reads sensibly', () => {
	expect(answeredLine({ asked_of_name: 'Ben', pick: 5 }, null)).toBe('Ben picked a suggestion');
});

test('the question and the answer get furigana', () => {
	const readings = { 食: 'た' };
	const waiting = render(OpinionStatus, {
		props: { opinion: { ...opinion, question: '食べるでいい？' }, suggestions: [], readings, oncancel: () => {} }
	}).body;
	expect(waiting).toMatch(/<ruby[^>]*>食<rt>た<\/rt><\/ruby>/);
	const answered = { ...opinion, waiting: false, answered_at: 'x', pick: null, answer: '食べるが自然です。' };
	const body = render(OpinionStatus, { props: { opinion: answered, suggestions: [], readings, oncancel: () => {} } }).body;
	expect(body).toMatch(/<ruby[^>]*>食<rt>た<\/rt><\/ruby>/);
});

test('closed, the panel is one button and loads nobody until it opens', () => {
	const { body } = render(AskOpinion, { props: { target, onasked: () => {} } });
	expect(body).toMatch(/<button[^>]*aria-expanded="false"[^>]*>Ask for a second opinion<\/button>/);
	expect(body).not.toContain('<form');
	expect(body).not.toContain('Loading');
	const source = readFileSync(new URL('./AskOpinion.svelte', import.meta.url), 'utf8');
	expect(source).not.toMatch(/onMount/);
	expect(source).toMatch(/async function open\(\)[\s\S]*?getCandidates\(target\)/);
});

test('roles read as words, not codes', () => {
	const { body } = render(AskOpinion, {
		props: { target, onasked: () => {}, open: true, candidates: [...candidates, { user: 3, name: 'Martin', role: 'admin', seen: null }] }
	});
	expect(body).toContain('Teacher · approved it earlier');
	expect(body).toContain('Native speaker · ');
	expect(body).toContain('Owner · ');
	expect(roleLabel('reviewer')).toBe('Reviewer');
	expect(roleLabel('someone')).toBe('someone');
});

test('the lead fits one suggestion or several', () => {
	expect(askLead(1)).toBe('They see the suggestion and say whether it works. You still decide.');
	expect(askLead(2)).toBe('They see both suggestions and pick one, or say why neither works. You still decide.');
	expect(askLead(3)).toBe(askLead(2));
	const one = render(AskOpinion, { props: { target, onasked: () => {}, open: true, candidates, count: 1 } }).body;
	expect(one).toContain('They see the suggestion and say whether it works.');
});

test('the inbox passes readings to the status and how many suggestions there are to the panel', () => {
	const source = readFileSync(new URL('../routes/inbox/+page.svelte', import.meta.url), 'utf8');
	expect(source).toMatch(/<OpinionStatus[^>]*\{readings\}/);
	expect(source).toMatch(/<AskOpinion[\s\S]*?count=\{openChanges\(group\.items\)\.length\}/);
	expect(source).toMatch(/hasOpen = \(items: InboxSuggestion\[\]\) => openChanges\(items\)\.length > 0/);
});
