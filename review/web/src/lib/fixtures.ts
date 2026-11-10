// Shared test fixtures.
import type { InboxSuggestion, Suggestion } from './api.ts';

/** A suggestion to add an example. */
export const addition: Suggestion = {
	id: 1, action: 'add', dataset: 'verbs', kind: 'example', item_id: 'new001', entry_id: 'たべる',
	item_title: '食べてから寝ます。', author_name: 'Aiko', mine: false, status: 'open', base_hash: '',
	proposed: { id: 'new001', form: 'te', jp: '食べてから寝ます。', en: 'I eat, then sleep.' },
	furigana: null, dropped_blanks: 0, comment: '', admin_edit: null, created_at: '', decided_at: null,
	stale: false, gone: false, parent_kind: 'entry', parent_id: 'たべる', landed: false, last_read: null, comments: []
};

/** The same as it appears in the inbox: with the target as it is now. */
export const inboxSuggestion: InboxSuggestion = { ...addition, current: null };
