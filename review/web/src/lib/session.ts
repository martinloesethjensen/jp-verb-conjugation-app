// The signed-in user, set once by the root layout. Pages render only after it is known.
import { createContext } from 'svelte';
import type { Me } from './api.ts';

export type Session = {
	/** The signed-in user. */
	me: () => Me;
	/** Replace it after the user changes something about themselves (their name). */
	update: (me: Me) => void;
};

export const [getSession, setSession] = createContext<Session>();
