import { describe, expect, test } from 'vitest';
import { render } from 'svelte/server';
import type { UserSettings } from './api.ts';
import { availableSteps, shouldTour, shouldWelcome, TOUR_STEPS } from './tour.ts';
import TourGuide from './TourGuide.svelte';
import WelcomeDialog from './WelcomeDialog.svelte';

const base: UserSettings = { welcome_seen_at: null, tour_seen_at: null, tips_on: true, tips_dismissed: [], shortcuts_on: true };
const welcomed = { ...base, welcome_seen_at: '2026-11-11T10:00:00.000Z' };
const done = { ...welcomed, tour_seen_at: '2026-11-11T10:05:00.000Z' };

describe('when the tour shows', () => {
	test('new: welcome; welcomed: tour; done: neither; reset: welcome again', () => {
		expect([shouldWelcome(base, true, false), shouldTour(base, true, false)]).toEqual([true, false]);
		expect([shouldWelcome(welcomed, true, false), shouldTour(welcomed, true, false)]).toEqual([false, true]);
		expect([shouldWelcome(done, true, false), shouldTour(done, true, false)]).toEqual([false, false]);
		const reset = { ...done, welcome_seen_at: null, tour_seen_at: null };
		expect(shouldWelcome(reset, true, false)).toBe(true);
	});

	test('never before settings load, and not on a phone', () => {
		expect(shouldWelcome(base, false, false)).toBe(false);
		expect(shouldTour(welcomed, false, false)).toBe(false);
		expect(shouldWelcome(base, true, true)).toBe(false);
		expect(shouldTour(welcomed, true, true)).toBe(false);
	});

	test('steps_without_a_target_are_skipped', () => {
		expect(availableSteps((t) => t !== 'approve').map((s) => s.target)).toEqual(['list', 'item', 'suggest', 'bell']);
		expect(TOUR_STEPS.map((s) => s.target)).toEqual(['list', 'item', 'approve', 'suggest', 'bell']);
	});

	test('the copy never says Martin decides', () => {
		expect(TOUR_STEPS.find((s) => s.target === 'suggest')!.text).toContain('Another teacher or Martin accepts it');
		expect(JSON.stringify(TOUR_STEPS)).not.toMatch(/Martin decides/);
	});
});

describe('the pieces', () => {
	test('the welcome dialog offers Start and Skip the tour', () => {
		const { body } = render(WelcomeDialog, { props: { open: true, onstart: () => {}, onskip: () => {} } });
		expect(body).toContain('Welcome to Kotoba Table review');
		expect(body).toContain('>Start<');
		expect(body).toContain('Skip the tour');
	});

	test('the guide starts at the first step with Back disabled', () => {
		const { body } = render(TourGuide, { props: { steps: TOUR_STEPS, ondone: () => {} } });
		expect(body).toContain('Your queue');
		expect(body).toMatch(/<button[^>]*disabled[^>]*>Back</);
		expect(body).toContain('>Next<');
		expect(body).toContain('>Skip<');
		expect(body).toContain('1 of 5');
	});
});
