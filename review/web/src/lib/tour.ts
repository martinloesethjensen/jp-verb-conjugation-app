// The first-run tour: a welcome on Home, then five highlighted steps the first time someone opens a queue.
// Phones get their own welcome cards instead (PhoneWelcome).
import type { UserSettings } from './api.ts';

/** Narrower than this, a person gets the phone cards instead of the welcome and the highlighted tour. The
 * queue page puts its item list in a sheet below the same width, so the tour's targets aren't there. */
export const ONBOARDING_PHONE = 'max-width: 959px';

export type TourTarget = 'list' | 'item' | 'approve' | 'suggest' | 'bell';
export type TourStep = { target: TourTarget; title: string; text: string };

export const TOUR_STEPS: TourStep[] = [
	{
		target: 'list',
		title: 'Your queue',
		text: 'These are the items Martin picked for you. Done ones get a check, and you can jump to any of them.'
	},
	{
		target: 'item',
		title: 'Read it like a teacher',
		text: 'Check the Japanese, the reading and the English. Is it natural? Is it right?'
	},
	{ target: 'approve', title: 'Looks right', text: "If it's right, stamp it with your seal. You can undo it." },
	{
		target: 'suggest',
		title: 'Suggest a change',
		text: "If something's off, fix it in place. Another teacher or Martin accepts it before it reaches the app."
	},
	{
		target: 'bell',
		title: 'Replies',
		text: 'When someone answers you, or your suggestion is accepted or declined, the bell shows a red count.'
	}
];

export const TOUR_CLOSING = {
	title: "You're ready",
	text: 'Find this tour again, tips and keyboard shortcuts in Settings › Help.'
};

/** The steps whose target is on the page; a missing one is skipped, never waited for. */
export function availableSteps(has: (target: TourTarget) => boolean): TourStep[] {
	return TOUR_STEPS.filter((s) => has(s.target));
}

export function shouldWelcome(s: UserSettings, loaded: boolean, phone: boolean): boolean {
	return loaded && !phone && s.welcome_seen_at === null && s.tour_seen_at === null;
}

export function shouldTour(s: UserSettings, loaded: boolean, phone: boolean): boolean {
	return loaded && !phone && s.welcome_seen_at !== null && s.tour_seen_at === null;
}

/** On a phone, four cards instead of the welcome and the highlighted tour. */
export const PHONE_CARDS: { title: string; text: string }[] = [
	{ title: 'Welcome to Kotoba Table review', text: "You help make the app's Japanese right. Thank you for being here." },
	{
		title: 'Read it like a teacher',
		text: 'Each item is a word, a sentence or a grammar point. Check the Japanese, the reading and the English.'
	},
	{ title: 'Stamp it or fix it', text: 'Looks right stamps your seal. Suggest a change fixes it in place.' },
	{
		title: 'What happens next',
		text: 'Another teacher or Martin accepts your change. It reaches the app with the next data release, and the bell tells you.'
	}
];

export function shouldPhoneWelcome(s: UserSettings, loaded: boolean, phone: boolean): boolean {
	return loaded && phone && s.tour_seen_at === null;
}
