import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { expect, test } from 'vitest';
import { canAskOpinion, canDecide, decidesAll, declineLabel, editableFields, mayDecide, ownSuggestionLine, TEACHER_DECIDES } from './roles.ts';
import type { Field } from './api.ts';

test('teachers, natives and the owner open the inbox; only teachers and the owner decide everything', () => {
	expect(canDecide('teacher')).toBe(true);
	expect(canDecide('native')).toBe(true);
	expect(canDecide('admin')).toBe(true);
	expect(canDecide('reviewer')).toBe(false);
	expect(decidesAll('teacher')).toBe(true);
	expect(decidesAll('admin')).toBe(true);
	expect(decidesAll('native')).toBe(false);
	expect(decidesAll('reviewer')).toBe(false);
});

test('a native decides only what the Worker marks Japanese-only', () => {
	expect(mayDecide('native', { japanese_only: true })).toBe(true);
	expect(mayDecide('native', { japanese_only: false })).toBe(false);
	expect(mayDecide('teacher', { japanese_only: false })).toBe(true);
	expect(mayDecide('admin', { japanese_only: false })).toBe(true);
	expect(mayDecide('reviewer', { japanese_only: true })).toBe(false);
	expect(TEACHER_DECIDES).toBe('A teacher or Martin decides this one.');
});

test("a native's Edit then accept shows only the Japanese fields", () => {
	const field = (name: string): Field => ({ name, input: 'text', optional: false, choices: [], default: null });
	const fields = [field('jp'), field('en'), field('form')];
	expect(editableFields('native', fields).map((f) => f.name)).toEqual(['jp']);
	expect(editableFields('teacher', fields).map((f) => f.name)).toEqual(['jp', 'en', 'form']);
	expect(editableFields('admin', fields)).toHaveLength(3);
});

test('natives get decision buttons only where they may decide, and the owner can make someone a native', () => {
	const page = readFileSync(join(SRC, 'routes/inbox/+page.svelte'), 'utf8');
	expect(page).toMatch(/\{:else if !mayDecide\(me\(\)\.role, s\)\}[\s\S]*TEACHER_DECIDES/);
	expect(page).toContain('editableFields(me().role');
	const admin = readFileSync(join(SRC, 'routes/admin/+page.svelte'), 'utf8');
	expect(admin).toContain('<option value="native">also accept Japanese fixes</option>');
});

const SRC = new URL('..', import.meta.url).pathname;

function files(dir: string): string[] {
	return readdirSync(dir).flatMap((name) => {
		const path = join(dir, name);
		if (statSync(path).isDirectory()) return files(path);
		return /\.(svelte|ts)$/.test(name) && !name.endsWith('.test.ts') ? [path] : [];
	});
}

test('the inbox lives at /inbox for teachers, and own suggestions get no decision buttons', () => {
	expect(existsSync(join(SRC, 'routes/inbox/+page.svelte'))).toBe(true);
	expect(existsSync(join(SRC, 'routes/admin/inbox'))).toBe(false);
	const page = readFileSync(join(SRC, 'routes/inbox/+page.svelte'), 'utf8');
	expect(page).toContain('canDecide(');
	expect(page).toMatch(/\{#if s\.mine\}[\s\S]*ownSuggestionLine\(/);
});

test("the owner's own suggestion waits for a teacher, so the line says so", () => {
	expect(ownSuggestionLine('teacher')).toBe('Yours. Another teacher or Martin accepts it.');
	expect(ownSuggestionLine('admin')).toBe('Yours. A teacher accepts it.');
	expect(ownSuggestionLine('native')).toBe('Yours. Someone else accepts it.');
});

test('no page still calls the admin inbox or says Martin decides', () => {
	for (const file of files(SRC)) {
		const text = readFileSync(file, 'utf8');
		for (const old of ['/api/admin/inbox', '/api/admin/decide', 'Leave a note for Martin', 'Sent. Martin will look at it.', 'note for Martin', "Martin's version"]) {
			expect(text, `${file}: ${old}`).not.toContain(old);
		}
	}
});

test('teachers and the owner ask for a second opinion; natives and reviewers do not', () => {
	expect(canAskOpinion('admin')).toBe(true);
	expect(canAskOpinion('teacher')).toBe(true);
	expect(canAskOpinion('native')).toBe(false);
	expect(canAskOpinion('reviewer')).toBe(false);
});

test('Decline says the reply goes with it when the reply box has text', () => {
	expect(declineLabel('')).toBe('Decline');
	expect(declineLabel('   ')).toBe('Decline');
	expect(declineLabel('Too literal.')).toBe('Decline with reply');
});

test("the inbox's Decline sends the card's reply draft and clears it", () => {
	const page = readFileSync(join(SRC, 'routes/inbox/+page.svelte'), 'utf8');
	expect(page).toMatch(/\{#snippet actions\(\{ draft, clear \}\)\}/);
	expect(page).toMatch(/decline\(s\.id, draft\)/);
	expect(page).toMatch(/clear\(\)/);
	expect(page).toContain('declineLabel(draft)');
	expect(page).not.toMatch(/decide\(s\.id, 'decline'\)/);
});
