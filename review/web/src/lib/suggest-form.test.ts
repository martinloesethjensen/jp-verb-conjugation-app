import { expect, test } from 'vitest';
import { render } from 'svelte/server';
import SuggestForm from './SuggestForm.svelte';
import type { Field } from './api.ts';

const fields = [{ name: 'en', input: 'text', optional: false, choices: [] }] as Field[];
const base = { fields, readings: {}, forms: {}, onsubmit: async () => {}, oncancel: () => {} };
const sendDisabled = /<button[^>]*class="primary[^"]*"[^>]*disabled/;

test('Send is disabled until something differs', () => {
	const { body } = render(SuggestForm, { props: { ...base, current: { en: 'I ate bread.' } } });
	expect(body).toMatch(sendDisabled);
	expect(body).not.toContain('Was:');
});

test('a changed field shows what it was, an undo and the red pen', () => {
	const { body } = render(SuggestForm, { props: { ...base, current: { en: 'I ate bread.' }, initial: { en: 'I used to eat bread.' } } });
	expect(body).toContain('Was: I ate bread.');
	expect(body).toMatch(/class="link[^"]*"[^>]*>Undo</);
	expect(body).toMatch(/<del[\s>]/);
	expect(body).not.toMatch(sendDisabled);
});

test('the reason field shows only when asked for', () => {
	expect(render(SuggestForm, { props: { ...base, current: { en: 'x' }, askWhy: true } }).body).toContain('Why? (optional, helps whoever decides)');
	expect(render(SuggestForm, { props: { ...base, current: { en: 'x' } } }).body).not.toContain('Why?');
});

test('an add form (nothing to compare with) shows no Was or red pen', () => {
	const { body } = render(SuggestForm, { props: { ...base, current: {}, initial: { en: 'A new one.' } } });
	expect(body).not.toContain('Was:');
	expect(body).not.toMatch(/<del[\s>]/);
	expect(body).not.toMatch(sendDisabled);
});

test('a draft carries typed values, readings and the reason into a new form', () => {
	const draft = { values: { en: 'I used to eat bread.' }, answers: {}, why: 'More natural.' };
	const { body } = render(SuggestForm, { props: { ...base, current: { en: 'I ate bread.' }, askWhy: true, draft } });
	expect(body).toMatch(/value="I used to eat bread\."/);
	expect(body).toContain('Was: I ate bread.');
	expect(body).toContain('More natural.');
});

test('Was shows Japanese with furigana', () => {
	const jp = [{ name: 'jp', input: 'text', optional: false, choices: [] }] as Field[];
	const { body } = render(SuggestForm, {
		props: { ...base, fields: jp, readings: { 食: 'た' }, current: { jp: '食べた。' }, initial: { jp: '食べていた。' } }
	});
	expect(body).toMatch(/Was: <span lang=\"ja\">[\s\S]*?<ruby[^>]*>食<rt>た<\/rt><\/ruby>/);
});
