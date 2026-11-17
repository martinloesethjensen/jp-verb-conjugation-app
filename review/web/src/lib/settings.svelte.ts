// The signed-in person's settings and onboarding progress, loaded with the session. A failed load keeps the
// defaults and marks nothing loaded, so shortcuts still work and no tour or tip nags on every page.
import { changeSettings, getSettings, type SettingsChange, type UserSettings } from './api.ts';

export const DEFAULT_SETTINGS: UserSettings = {
	welcome_seen_at: null,
	tour_seen_at: null,
	tips_on: true,
	tips_dismissed: [],
	shortcuts_on: true
};

class Settings {
	value = $state<UserSettings>({ ...DEFAULT_SETTINGS, tips_dismissed: [] });
	loaded = $state(false);

	get showTips() {
		return this.loaded && this.value.tips_on;
	}

	tipOpen(id: string) {
		return this.showTips && !this.value.tips_dismissed.includes(id);
	}

	async load() {
		try {
			this.value = await getSettings();
			this.loaded = true;
		} catch {
			// Defaults stay; see the comment above.
		}
	}

	#queue: Promise<unknown> = Promise.resolve();

	/** Shows the change at once and saves it; on failure puts the old value back and rethrows. Changes go one at
	 * a time, so a failed one never puts back a value that a later one has already saved. */
	change(change: SettingsChange): Promise<void> {
		const run = this.#queue.then(() => this.#apply(change));
		this.#queue = run.catch(() => {});
		return run;
	}

	async #apply(change: SettingsChange) {
		const before = this.value;
		this.value = {
			...before,
			...(change.tips_on === undefined ? {} : { tips_on: change.tips_on }),
			...(change.shortcuts_on === undefined ? {} : { shortcuts_on: change.shortcuts_on })
		};
		try {
			this.value = await changeSettings(change);
		} catch (error) {
			this.value = before;
			throw error;
		}
	}
}

export const settings = new Settings();
