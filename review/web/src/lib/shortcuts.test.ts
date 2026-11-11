import { describe, expect, test } from 'vitest';
import { render } from 'svelte/server';
import { isTyping, sendButton, shortcutFor, SHORTCUT_HELP } from './shortcuts.ts';
import KeyboardHelp from './KeyboardHelp.svelte';
import ReviewBar from './ReviewBar.svelte';
import type { EntryReview } from './review.svelte.ts';

const key = (k: string, mods: Partial<{ metaKey: boolean; ctrlKey: boolean; altKey: boolean; shiftKey: boolean }> = {}) => ({
	key: k,
	metaKey: false,
	ctrlKey: false,
	altKey: false,
	shiftKey: false,
	...mods
});

describe('the keymap', () => {
	test.each([
		['a', 'approve'],
		['A', 'approve'],
		['s', 'suggest'],
		['x', 'skip'],
		['n', 'note'],
		['u', 'undo'],
		['j', 'next'],
		['ArrowRight', 'next'],
		['k', 'previous'],
		['ArrowLeft', 'previous'],
		['o', 'open'],
		['r', 'reply'],
		['Escape', 'cancel']
	])('%s → %s', (k, action) => {
		expect(shortcutFor(key(k, { shiftKey: k === 'A' }), false)).toBe(action);
	});

	test('? opens help, and Cmd/Ctrl+Enter sends', () => {
		expect(shortcutFor(key('?', { shiftKey: true }), false)).toBe('help');
		expect(shortcutFor(key('Enter', { metaKey: true }), false)).toBe('send');
		expect(shortcutFor(key('Enter', { ctrlKey: true }), false)).toBe('send');
		expect(shortcutFor(key('Enter'), false)).toBeNull();
	});

	test('other modifier combinations do nothing', () => {
		expect(shortcutFor(key('a', { ctrlKey: true }), false)).toBeNull();
		expect(shortcutFor(key('n', { altKey: true }), false)).toBeNull();
		expect(shortcutFor(key('j', { metaKey: true }), false)).toBeNull();
		expect(shortcutFor(key('q'), false)).toBeNull();
	});

	test('letters_do_nothing_while_typing', () => {
		for (const k of ['a', 'j', 'ArrowRight', 'r']) expect(shortcutFor(key(k), true)).toBeNull();
		expect(shortcutFor(key('?', { shiftKey: true }), true)).toBeNull();
		expect(shortcutFor(key('Escape'), true)).toBe('cancel');
		expect(shortcutFor(key('Enter', { ctrlKey: true }), true)).toBe('send');
	});

	test('isTyping knows fields', () => {
		const el = (tagName: string, isContentEditable = false) => ({ tagName, isContentEditable }) as unknown as EventTarget;
		expect(isTyping(el('INPUT'))).toBe(true);
		expect(isTyping(el('TEXTAREA'))).toBe(true);
		expect(isTyping(el('SELECT'))).toBe(true);
		expect(isTyping(el('DIV', true))).toBe(true);
		expect(isTyping(el('BUTTON'))).toBe(false);
		expect(isTyping(null)).toBe(false);
	});
});

describe('where the keys land', () => {
	const stub = { approvalsOf: () => [], suggestionsOf: () => [], approvedByMe: () => false, hashOf: () => 'h', isJustApproved: () => false } as unknown as EntryReview;
	const field = { name: 'en', input: 'text' as const, optional: false, choices: [] };

	test('the review bar marks its buttons, but not removal', () => {
		const { body } = render(ReviewBar, {
			props: { kind: 'example', id: 'x', value: {}, fields: [field], readings: {}, forms: {}, review: stub, onskip: async () => {} }
		});
		for (const name of ['approve', 'suggest', 'skip', 'note']) expect(body).toContain(`data-shortcut="${name}"`);
		expect(body).not.toMatch(/data-shortcut="[^"]*"[^>]*>Suggest removing it/);
	});

	test('the help lists every shortcut', () => {
		const { body } = render(KeyboardHelp, { props: { open: true, onclose: () => {} } });
		expect(body).toContain('Looks right');
		expect(body).toMatch(/<kbd[^>]*>A<\/kbd>/);
		expect(SHORTCUT_HELP.length).toBeGreaterThanOrEqual(11);
	});
});

describe('sending with the keyboard', () => {
	test('Cmd/Ctrl+Enter presses the form’s Send button only when it is enabled', () => {
		const form = (button: { disabled: boolean } | null) => ({ querySelector: () => button });
		const enabled = { disabled: false };
		expect(sendButton(form(enabled))).toBe(enabled);
		expect(sendButton(form({ disabled: true }))).toBeNull();
		expect(sendButton(form(null))).toBeNull();
		expect(sendButton(null)).toBeNull();
	});
});
