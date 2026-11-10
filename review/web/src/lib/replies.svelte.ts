// The signed-in person's replies: one store the header bell, Home and the Replies page share. It loads when
// the site does and after each navigation (no push). A failed load leaves it as it was, quietly.
import { getReplies, markAllRead, markRead, type Reply } from './api.ts';

class Replies {
	unread = $state(0);
	list = $state<Reply[]>([]);
	loaded = $state(false);
	#pending = new Set<number>();

	async refresh() {
		try {
			const answer = await getReplies();
			this.unread = answer.unread;
			this.list = answer.replies;
			this.loaded = true;
		} catch {
			// The bell stays as it was; nothing else on the page depends on it.
		}
	}

	/** Marks a thread read. Calls in the same tick go out as one request. */
	read(id: number) {
		const first = this.#pending.size === 0;
		this.#pending.add(id);
		if (first) queueMicrotask(() => this.#flush());
	}

	async #flush() {
		const ids = [...this.#pending];
		this.#pending.clear();
		try {
			const answer = await markRead(ids);
			this.#settle(answer.unread, (r) => ids.includes(r.suggestion_id));
		} catch {
			// Still unread; the next visit tries again.
		}
	}

	async readAll() {
		try {
			const answer = await markAllRead();
			this.#settle(answer.unread, () => true);
		} catch {
			// Nothing changes.
		}
	}

	#settle(unread: number, read: (r: Reply) => boolean) {
		this.unread = unread;
		this.list = this.list.map((r) => (read(r) ? { ...r, unread: false } : r));
	}
}

export const replies = new Replies();

/** The line a list shows for a reply. */
export function replyText(r: Reply): string {
	if (r.what === 'accepted') return `${r.by_name} accepted your suggestion`;
	if (r.what === 'declined') return `${r.by_name} declined your suggestion`;
	return `${r.by_name} replied`;
}

export function groupReplies(list: Reply[]): { fresh: Reply[]; earlier: Reply[] } {
	return { fresh: list.filter((r) => r.unread), earlier: list.filter((r) => !r.unread) };
}
