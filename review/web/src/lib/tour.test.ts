import { readFileSync } from 'node:fs';
import { describe, expect, test } from 'vitest';
import { render } from 'svelte/server';
import type { UserSettings } from './api.ts';
import { availableSteps, ONBOARDING_PHONE, PHONE_CARDS, shouldPhoneWelcome, shouldTour, shouldWelcome, TOUR_STEPS } from './tour.ts';
import PhoneWelcome from './PhoneWelcome.svelte';
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

describe('the phone welcome', () => {
	test('shows on a phone until the tour is done, and again after a reset', () => {
		expect(shouldPhoneWelcome(base, true, true)).toBe(true);
		expect(shouldPhoneWelcome(welcomed, true, true)).toBe(true);
		expect(shouldPhoneWelcome(done, true, true)).toBe(false);
		expect(shouldPhoneWelcome({ ...done, tour_seen_at: null, welcome_seen_at: null }, true, true)).toBe(true);
		expect(shouldPhoneWelcome(base, true, false)).toBe(false);
		expect(shouldPhoneWelcome(base, false, true)).toBe(false);
	});

	test('four cards with dots, Skip and Next; the last says Start reviewing', () => {
		const first = render(PhoneWelcome, { props: { ondone: () => {} } }).body;
		expect(first.match(/class="dot[ "]/g)?.length).toBe(4);
		expect(first).toContain(PHONE_CARDS[0].title);
		expect(first).toContain('>Skip<');
		expect(first).toContain('>Next<');
		const last = render(PhoneWelcome, { props: { ondone: () => {}, start: 3 } }).body;
		expect(last).toContain('Start reviewing');
		expect(last).toContain(PHONE_CARDS[3].title);
		expect(PHONE_CARDS[3].text).toContain('Another teacher or Martin accepts your change');
	});
});

describe('one idea of a phone', () => {
	const read = (path: string) => readFileSync(new URL(path, import.meta.url), 'utf8');
	test('Home and the queue decide onboarding with the same width', () => {
		expect(ONBOARDING_PHONE).toBe('max-width: 959px');
		expect(read('../routes/+page.svelte')).toContain('new MediaQuery(ONBOARDING_PHONE)');
		expect(read('../routes/queue/+page.svelte')).toContain('new MediaQuery(ONBOARDING_PHONE)');
	});

	test('the thread tip sits on the normal item page, not only on removed items', () => {
		const page = read('../routes/item/+page.svelte');
		expect(page.slice(page.indexOf('class="item-header"'))).toContain('<Tip id="thread"');
	});
});
