// Keyboard shortcuts on the queue page. A key presses the same button a mouse would (the buttons carry
// `data-shortcut`), so a shortcut can never do something the page doesn't offer.

export type Shortcut =
	| 'approve'
	| 'suggest'
	| 'skip'
	| 'note'
	| 'undo'
	| 'next'
	| 'previous'
	| 'open'
	| 'reply'
	| 'cancel'
	| 'send'
	| 'help';

type Key = { key: string; metaKey: boolean; ctrlKey: boolean; altKey: boolean; shiftKey: boolean };

const LETTERS: Record<string, Shortcut> = {
	a: 'approve',
	s: 'suggest',
	x: 'skip',
	n: 'note',
	u: 'undo',
	j: 'next',
	arrowright: 'next',
	k: 'previous',
	arrowleft: 'previous',
	o: 'open',
	r: 'reply'
};

/** The shortcut for a key press, or null. While `typing`, only Esc and Cmd/Ctrl+Enter count. */
export function shortcutFor(e: Key, typing: boolean): Shortcut | null {
	if (e.key === 'Escape') return 'cancel';
	if (e.key === 'Enter') return (e.metaKey || e.ctrlKey) && !e.altKey ? 'send' : null;
	if (typing || e.metaKey || e.ctrlKey || e.altKey) return null;
	if (e.key === '?') return 'help';
	return LETTERS[e.key.toLowerCase()] ?? null;
}

/** The focus is in somewhere you type: letters there are text, not shortcuts. */
export function isTyping(target: EventTarget | null): boolean {
	if (!target) return false;
	const el = target as { tagName?: string; isContentEditable?: boolean };
	return ['INPUT', 'TEXTAREA', 'SELECT'].includes(el.tagName ?? '') || el.isContentEditable === true;
}

/** What the help dialog lists, in the spec's order. */
export const SHORTCUT_HELP: [keys: string[], what: string][] = [
	[['A'], 'Looks right'],
	[['S'], 'Suggest a change'],
	[['X'], 'Not sure, skip'],
	[['N'], 'Leave a note'],
	[['U'], 'Undo your approval'],
	[['J', '→'], 'Next item'],
	[['K', '←'], 'Previous item'],
	[['O'], 'Open the whole entry'],
	[['R'], 'Reply'],
	[['Esc'], 'Cancel or close'],
	[['⌘', 'Enter'], 'Send (Ctrl+Enter on Windows and Linux)'],
	[['?'], 'Show these shortcuts']
];
