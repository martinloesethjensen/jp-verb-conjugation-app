// Who may do what on the site (the Roles table in the polish spec). The Worker enforces every rule; these
// only decide what the pages show.
import type { Role } from './api.ts';

/** Accepts and declines other people's suggestions: teachers and the owner. */
export const canDecide = (role: Role) => role === 'teacher' || role === 'admin';

/** Shown on your own open suggestion in the inbox, in place of Accept and Decline. */
export const OWN_SUGGESTION_LINE = 'Yours. Another teacher or Martin accepts it.';
