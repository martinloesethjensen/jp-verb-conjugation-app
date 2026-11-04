// The signed-in user, set once by the root layout. Pages render only after it is known.
import { createContext } from 'svelte';
import type { Me } from './api.ts';

export const [getMe, setMe] = createContext<() => Me>();
