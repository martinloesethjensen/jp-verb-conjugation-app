import { readFileSync } from 'node:fs';
import { expect, test } from 'vitest';

test('"Open the whole entry" is a 44px target', () => {
	const source = readFileSync(new URL('./ReviewCard.svelte', import.meta.url), 'utf8');
	const rule = source.match(/\n\t\.what a \{([^}]*)\}/)?.[1] ?? '';
	expect(rule).toMatch(/display: inline-flex/);
	expect(rule).toMatch(/min-height: 44px/);
});
