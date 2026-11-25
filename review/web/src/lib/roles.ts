// Who may do what on the site (the Roles table in the polish spec). The Worker enforces every rule; these
// only decide what the pages show.
import type { Field, Role } from './api.ts';
import { JAPANESE_FIELDS } from './labels.ts';

/** Opens the inbox and decides some suggestions: teachers, natives and the owner. */
export const canDecide = (role: Role) => role === 'teacher' || role === 'native' || role === 'admin';

/** Decides every kind of suggestion: teachers and the owner. */
export const decidesAll = (role: Role) => role === 'teacher' || role === 'admin';

/** May decide this suggestion (own ones aside): a native only a change the Worker marks `japanese_only`. */
export const mayDecide = (role: Role, s: { japanese_only: boolean }) =>
	decidesAll(role) || (role === 'native' && s.japanese_only);

/** The fields someone may edit in Edit then accept: a native only the Japanese ones. */
export const editableFields = (role: Role, fields: Field[]) =>
	decidesAll(role) ? fields : fields.filter((f) => JAPANESE_FIELDS.has(f.name));

/** Shown to a native, in place of the decision buttons, on a suggestion that changes more than Japanese. */
export const TEACHER_DECIDES = 'A teacher or Martin decides this one.';

/** Shown on your own open suggestion in the inbox, in place of Accept and Decline. The owner can't accept
 * their own either, so theirs waits for a teacher; a native's may go to another native or a teacher. */
export const ownSuggestionLine = (role: Role) =>
	role === 'admin'
		? 'Yours. A teacher accepts it.'
		: role === 'native'
			? 'Yours. Someone else accepts it.'
			: 'Yours. Another teacher or Martin accepts it.';

/** Asks a colleague for a second opinion on an item's open suggestions: teachers and the owner. */
export const canAskOpinion = (role: Role) => role === 'teacher' || role === 'admin';
