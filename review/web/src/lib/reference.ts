// The furigana dictionary and form labels, fetched once per page load and shared by every component.
import { getReference, type Reference } from './api.ts';

let pending: Promise<Reference> | undefined;

/** The reference data, or empty maps when it isn't loaded or can't be fetched (text shows without ruby). */
export function loadReference(): Promise<Reference> {
	pending ??= getReference().catch(() => ({ readings: {}, forms: {}, fields: {}, add_fields: {}, add_parents: {} }));
	return pending;
}
