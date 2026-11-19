import { expect, test } from 'vitest';
import { render } from 'svelte/server';
import OpinionCard from './OpinionCard.svelte';
import { canAnswer, cardMode, NEITHER, pickable } from './opinions.ts';
import { addition } from './fixtures.ts';
import type { Opinion, Suggestion } from './api.ts';

const opinion: Opinion = {
	id: 1, dataset: 'verbs', kind: 'example', item_id: 'new001', entry_id: 'たべる', item_title: '食べてから寝ます。', anchor_id: 1,
	asked_by_name: 'Martin', asked_of_name: 'Yumi', mine_asked: false, mine_to_answer: true, question: 'Which reads better?',
	created_at: '2026-11-17 09:00:00', answered_at: null, pick: null, answer: '', cancelled_at: null, waiting: true
};
const change = (id: number, author: string, jp: string): Suggestion => ({
	...addition, id, action: 'change', author_name: author, proposed: { jp }
});
const suggestions = [change(1, 'Aiko', '食べてから、寝ます。'), change(2, 'Kenji', '食べた後で寝ます。')];
const current = { jp: '食べてから寝ます。' };
const props = { suggestions, current, names: ['jp'], onanswered: () => {} };

test('Send needs a pick, and for Neither a reason', () => {
	expect(canAnswer(null, 'because')).toBe(false);
	expect(canAnswer(1, '')).toBe(true);
	expect(canAnswer(NEITHER, '  ')).toBe(false);
	expect(canAnswer(NEITHER, 'both are stiff')).toBe(true);
});

test('only open changes can be picked', () => {
	const note = { ...suggestions[0], id: 3, action: 'note' as const };
	const declined = { ...suggestions[0], id: 4, status: 'declined' as const };
	expect(pickable([...suggestions, note, declined]).map((s) => s.id)).toEqual([1, 2]);
});

test('the card mode follows who is asked and whether it is still open', () => {
	expect(cardMode(opinion)).toBe('answer');
	expect(cardMode({ ...opinion, waiting: false })).toBe('decided');
	expect(cardMode({ ...opinion, waiting: false, answered_at: 'x' })).toBe('status');
	expect(cardMode({ ...opinion, mine_to_answer: false })).toBe('status');
	expect(cardMode({ ...opinion, waiting: false, cancelled_at: 'x' })).toBe('none');
});

test('the asked person gets the suggestions, Neither, a reason and a disabled Send', () => {
	const { body } = render(OpinionCard, { props: { opinion, ...props } });
	expect(body).toContain('role="radiogroup"');
	expect(body).toContain('Aiko');
	expect(body).toContain('Kenji');
	expect(body).toContain('Neither');
	expect(body).toContain('<textarea');
	expect(body).toContain('Which reads better?');
	expect(body).toMatch(/<button[^>]*type="submit"[^>]*disabled/);
});

test('once the item is decided there is only a thank-you and no form', () => {
	const { body } = render(OpinionCard, { props: { opinion: { ...opinion, waiting: false }, ...props } });
	expect(body).toContain('Already decided. Thanks anyway.');
	expect(body).not.toContain('<form');
	expect(body).not.toContain('role="radiogroup"');
});

test('everyone else sees the status line only', () => {
	const asker = { ...opinion, mine_to_answer: false, mine_asked: true };
	const waiting = render(OpinionCard, { props: { opinion: asker, ...props } }).body;
	expect(waiting).toContain("Waiting for Yumi's opinion");
	expect(waiting).not.toContain('<form');
	const answered = render(OpinionCard, { props: { opinion: { ...asker, waiting: false, answered_at: 'x', pick: 2 }, ...props } }).body;
	expect(answered).toContain("Yumi picked Kenji's suggestion");
	expect(render(OpinionCard, { props: { opinion: { ...asker, cancelled_at: 'x', waiting: false }, ...props } }).body).not.toContain('Yumi');
});
