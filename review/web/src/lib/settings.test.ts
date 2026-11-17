import { afterEach, describe, expect, test, vi } from 'vitest';
import { render } from 'svelte/server';
import { settings } from './settings.svelte.ts';
import RoleSummary from './RoleSummary.svelte';
import Tip, { TIP_TEXT } from './Tip.svelte';

const json = (status: number, body: unknown) =>
	new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

const DEFAULTS = { welcome_seen_at: null, tour_seen_at: null, tips_on: true, tips_dismissed: [], shortcuts_on: true };

afterEach(() => {
	vi.unstubAllGlobals();
	settings.value = { ...DEFAULTS, tips_dismissed: [] };
	settings.loaded = false;
});

describe('the settings store', () => {
	test('a_failed_load_keeps_defaults_and_shows_no_onboarding', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => Promise.reject(new Error('offline'))));
		await settings.load();
		expect(settings.loaded).toBe(false);
		expect(settings.value.shortcuts_on).toBe(true);
		expect(settings.showTips).toBe(false);
		expect(settings.tipOpen('inbox')).toBe(false);
	});

	test('a loaded store opens tips that are on and not dismissed', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => json(200, { ...DEFAULTS, tips_dismissed: ['thread'] })));
		await settings.load();
		expect(settings.loaded).toBe(true);
		expect(settings.tipOpen('inbox')).toBe(true);
		expect(settings.tipOpen('thread')).toBe(false);
	});

	test('a_failed_change_puts_the_old_value_back', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => json(500, { error: 'the database is unavailable' })));
		settings.loaded = true;
		await expect(settings.change({ shortcuts_on: false })).rejects.toBeTruthy();
		expect(settings.value.shortcuts_on).toBe(true);
	});

	test('a change takes the answer as the new value', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => json(200, { ...DEFAULTS, shortcuts_on: false })));
		settings.loaded = true;
		await settings.change({ shortcuts_on: false });
		expect(settings.value.shortcuts_on).toBe(false);
	});
});

describe('RoleSummary', () => {
	test.each([
		['reviewer', 'Reviewer: you approve items, suggest changes, leave notes and reply.'],
		['teacher', "Teacher: you also accept or decline other people's suggestions."],
		['admin', 'Owner: you also manage reviewers, queues, stamps and exports.']
	] as const)('%s', (role, text) => {
		expect(render(RoleSummary, { props: { role } }).body.replaceAll('&#39;', "'")).toContain(text);
	});
});

describe('Tip', () => {
	const props = { id: 'inbox', text: 'Each suggestion is decided on its own.' };

	test('shows with Got it while it is open', async () => {
		settings.loaded = true;
		const { body } = render(Tip, { props });
		expect(body).toContain('Each suggestion is decided on its own.');
		expect(body).toContain('Got it');
	});

	test('a dismissed tip renders nothing', () => {
		settings.loaded = true;
		settings.value = { ...DEFAULTS, tips_dismissed: ['inbox'] };
		expect(render(Tip, { props }).body).not.toContain('Got it');
	});

	test('nothing when tips are off or settings failed to load', () => {
		settings.loaded = true;
		settings.value = { ...DEFAULTS, tips_dismissed: [], tips_on: false };
		expect(render(Tip, { props }).body).not.toContain('Got it');
		settings.value = { ...DEFAULTS, tips_dismissed: [] };
		settings.loaded = false;
		expect(render(Tip, { props }).body).not.toContain('Got it');
	});

	test('the two tips have their copy', () => {
		expect(TIP_TEXT.inbox).toBe(
			'Each suggestion is decided on its own. Edit then accept fixes one before accepting it, and your reply goes to everyone in the thread.'
		);
		expect(TIP_TEXT.thread).toBe(
			'Reply under a suggestion to talk it through. Its author and everyone who replied are told.'
		);
	});
});

test('changes go one at a time, so a failed one never undoes the next', async () => {
	let fail: () => void = () => {};
	const calls: unknown[] = [];
	vi.stubGlobal(
		'fetch',
		vi.fn(async (_path: string, init: RequestInit) => {
			calls.push(JSON.parse(String(init.body)));
			if (calls.length === 1) {
				return new Promise<Response>((_, reject) => (fail = () => reject(new Error('offline'))));
			}
			return json(200, { ...DEFAULTS, tips_on: false });
		})
	);
	settings.loaded = true;
	const a = settings.change({ shortcuts_on: false }).catch(() => 'failed');
	const b = settings.change({ tips_on: false });
	await vi.waitFor(() => expect(calls.length).toBe(1));
	fail();
	expect(await a).toBe('failed');
	await b;
	expect(calls).toEqual([{ shortcuts_on: false }, { tips_on: false }]);
	expect(settings.value.shortcuts_on).toBe(true);
	expect(settings.value.tips_on).toBe(false);
});
