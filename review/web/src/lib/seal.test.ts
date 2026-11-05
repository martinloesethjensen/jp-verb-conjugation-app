import { afterEach, describe, expect, test, vi } from 'vitest';
import { render } from 'svelte/server';
import Seal from './Seal.svelte';
import RedPen from './RedPen.svelte';
import { prefersReducedMotion, shouldPress } from './seal.ts';

afterEach(() => vi.unstubAllGlobals());

describe('Seal', () => {
	test('renders 確認 and the name', () => {
		const { body } = render(Seal, { props: { name: 'Aiko' } });
		expect(body).toContain('確認');
		expect(body).toContain('Aiko');
		expect(body).not.toContain('press');
	});
	test('presses only when pressed flips to true', () => {
		expect(shouldPress(false, true, false)).toBe(true);
		expect(shouldPress(true, true, false)).toBe(false);
		expect(shouldPress(false, false, false)).toBe(false);
	});
	test('never presses with reduced motion', () => {
		expect(shouldPress(false, true, true)).toBe(false);
		vi.stubGlobal('matchMedia', (q: string) => ({ matches: q === '(prefers-reduced-motion: reduce)' }));
		expect(prefersReducedMotion()).toBe(true);
	});
});

describe('RedPen', () => {
	test('a changed particle is struck through and corrected', () => {
		const { body } = render(RedPen, {
			props: { before: { jp: '毎日学校に行きます' }, after: { jp: '毎日学校へ行きます' }, names: ['jp'] }
		});
		expect(body.match(/<del[^>]*>に<\/del>/g)).toHaveLength(1);
		expect(body.match(/<ins[^>]*>へ<\/ins>/g)).toHaveLength(1);
		expect(body).toContain('Japanese');
	});
});
