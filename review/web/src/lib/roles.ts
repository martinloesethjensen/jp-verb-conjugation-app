// Who may do what on the site (the Roles table in the polish spec). The Worker enforces every rule; these
// only decide what the pages show.
import type { Role } from './api.ts';

/** Accepts and declines other people's suggestions: teachers and the owner. */
export const canDecide = (role: Role) => role === 'teacher' || role === 'admin';

/** Shown on your own open suggestion in the inbox, in place of Accept and Decline. The owner can't accept
 * their own either, so theirs waits for a teacher. */
export const ownSuggestionLine = (role: Role) =>
	role === 'admin' ? 'Yours. A teacher accepts it.' : 'Yours. Another teacher or Martin accepts it.';
