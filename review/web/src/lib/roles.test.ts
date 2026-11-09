import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { expect, test } from 'vitest';
import { canDecide, ownSuggestionLine } from './roles.ts';

test('teachers and the owner decide; reviewers do not', () => {
	expect(canDecide('teacher')).toBe(true);
	expect(canDecide('admin')).toBe(true);
	expect(canDecide('reviewer')).toBe(false);
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
});

test('no page still calls the admin inbox or says Martin decides', () => {
	for (const file of files(SRC)) {
		const text = readFileSync(file, 'utf8');
		for (const old of ['/api/admin/inbox', '/api/admin/decide', 'Leave a note for Martin', 'Sent. Martin will look at it.', 'note for Martin', "Martin's version"]) {
			expect(text, `${file}: ${old}`).not.toContain(old);
		}
	}
});
