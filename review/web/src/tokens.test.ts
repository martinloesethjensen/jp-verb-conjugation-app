import { expect, test } from 'vitest';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { contrastRatio } from './lib/contrast.ts';

const here = new URL('.', import.meta.url).pathname;
const css = readFileSync(join(here, 'app.css'), 'utf8');

function cssVar(name: string): string {
	const match = css.match(new RegExp(`--${name}:\\s*([^;]+);`));
	if (!match) throw new Error(`--${name} is not defined in app.css`);
	return match[1].trim().toLowerCase();
}

function ruleBody(selector: string): string {
	const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
	const match = css.match(new RegExp(`(?:^|\\n)${escaped}\\s*\\{([^}]*)\\}`));
	if (!match) throw new Error(`no ${selector} rule in app.css`);
	return match[1];
}

function sourceFiles(dir = here): [string, string][] {
	const out: [string, string][] = [];
	for (const name of readdirSync(dir)) {
		const path = join(dir, name);
		if (statSync(path).isDirectory()) out.push(...sourceFiles(path));
		else if (/\.(svelte|css|ts)$/.test(name) && !path.endsWith('tokens.test.ts'))
			out.push([path, readFileSync(path, 'utf8')]);
	}
	return out;
}

test('contrastRatio follows WCAG', () => {
	expect(contrastRatio('#000000', '#FFFFFF')).toBeCloseTo(21, 5);
	expect(contrastRatio('#7C8390', '#F6F7F4')).toBeLessThan(4.5); // the old muted colour
});

test('tokens match the spec', () => {
	expect(cssVar('muted')).toBe('#5f6673');
	expect(cssVar('well')).toBe('#eceee9');
	expect(cssVar('radius')).toBe('16px');
	expect(cssVar('radius-input')).toBe('12px');
});

test('every text token passes 4.5:1 on paper and card', () => {
	for (const fg of ['ink', 'muted', 'red', 'green'])
		for (const bg of ['paper', 'card'])
			expect(contrastRatio(cssVar(fg), cssVar(bg)), `${fg} on ${bg}`).toBeGreaterThanOrEqual(4.5);
});

test('buttons and chips are pills with 44px targets', () => {
	expect(ruleBody('button')).toMatch(/min-height:\s*44px/);
	expect(ruleBody('button')).toMatch(/border-radius:\s*999px/);
	expect(ruleBody('.chip')).toMatch(/min-height:\s*44px/);
	expect(ruleBody('.chip')).toMatch(/border-radius:\s*999px/);
});

test('font stacks keep their fallbacks', () => {
	expect(cssVar('sans')).toContain('system-ui');
	expect(cssVar('mincho')).toContain('hiragino mincho pron');
});

test('the old muted colour and 6px radius are gone from src', () => {
	for (const [file, text] of sourceFiles()) {
		expect(text.toLowerCase(), file).not.toContain('#7c8390');
		expect(text, file).not.toMatch(/border-radius:\s*6px/);
	}
});

test('sheets slide up, and reduced motion still switches animations off', () => {
	expect(css).toMatch(/@keyframes sheet-up/);
	expect(css).toMatch(/prefers-reduced-motion: reduce[\s\S]*animation: none !important/);
});
