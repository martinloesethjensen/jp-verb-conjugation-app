import { afterEach, describe, expect, test, vi } from 'vitest';
import { render } from 'svelte/server';
import { settings } from './settings.svelte.ts';
import RoleSummary from './RoleSummary.svelte';

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
