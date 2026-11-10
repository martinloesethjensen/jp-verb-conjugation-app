// The signed-in person's replies: one store the header bell, Home and the Replies page share. It loads when
// the site does and after each navigation (no push). A failed load leaves it as it was, quietly.
import { getReplies, markAllRead, markRead, type Reply, type Suggestion } from './api.ts';

class Replies {
	unread = $state(0);
	list = $state<Reply[]>([]);
	loaded = $state(false);
	#pending = new Set<number>();
	/** Bumped by every read, so a refresh that started before one doesn't bring the old count back. */
	#reads = 0;

	async refresh() {
		const started = this.#reads;
		try {
			const answer = await getReplies();
			if (this.#reads !== started) return;
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
		this.#reads++;
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

/** The index of the first comment in `s` that someone else wrote since the viewer last looked; -1 when
 * there is none, or when the viewer isn't in the thread (`last_read` null). */
export function firstNew(s: Pick<Suggestion, 'comments' | 'last_read'>): number {
	const since = s.last_read;
	if (since == null) return -1;
	return s.comments.findIndex((c) => !c.mine && c.created_at > since);
}

/** The viewer's own suggestion was decided since they last looked. */
export function newDecision(s: Pick<Suggestion, 'mine' | 'status' | 'decided_at' | 'last_read'>): boolean {
	return (
		s.mine &&
		s.last_read != null &&
		(s.status === 'accepted' || s.status === 'declined') &&
		(s.decided_at ?? '') > s.last_read
	);
}
