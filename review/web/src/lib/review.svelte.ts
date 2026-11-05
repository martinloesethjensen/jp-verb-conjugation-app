// One entry's reviews: its parts' current hashes, approvals and suggestions, and the actions on them.
// Shared by the item page and the queue card, so both update the same way.
import {
	approve,
	comment,
	getReview,
	suggest,
	withdrawApproval,
	withdrawSuggestion,
	type Approval,
	type ReviewPart,
	type Suggestion,
	type SuggestionAction,
	type Target
} from './api.ts';

const key = (kind: string, id: string) => `${kind}/${id}`;

export class EntryReview {
	dataset: string;
	entryId: string;
	parts = $state<ReviewPart[]>([]);
	approvals = $state<Approval[]>([]);
	suggestions = $state<Suggestion[]>([]);
	/** The target the viewer approved last in this visit, so its seal presses once. */
	justApproved = $state<string | null>(null);

	constructor(dataset: string, entryId: string) {
		this.dataset = dataset;
		this.entryId = entryId;
	}

	async load() {
		const review = await getReview(this.dataset, this.entryId);
		this.parts = review.parts;
		this.approvals = review.approvals;
		this.suggestions = review.suggestions;
	}

	target(kind: string, id: string): Target {
		return { dataset: this.dataset, kind, id };
	}

	hashOf(kind: string, id: string): string | undefined {
		return this.parts.find((p) => p.kind === kind && p.item_id === id)?.content_hash;
	}

	approvalsOf(kind: string, id: string): Approval[] {
		return this.approvals.filter((a) => a.kind === kind && a.item_id === id);
	}

	/** Newest first, without withdrawn ones. */
	suggestionsOf(kind: string, id: string): Suggestion[] {
		return this.suggestions.filter((s) => s.kind === kind && s.item_id === id && s.status !== 'withdrawn');
	}

	approvedByMe(kind: string, id: string): boolean {
		return this.approvalsOf(kind, id).some((a) => a.mine && a.current);
	}

	isJustApproved(kind: string, id: string): boolean {
		return this.justApproved === key(kind, id);
	}

	async approve(kind: string, id: string) {
		const hash = this.hashOf(kind, id);
		if (!hash) return;
		this.approvals = (await approve(this.target(kind, id), hash)).approvals;
		this.justApproved = key(kind, id);
	}

	async undo(kind: string, id: string) {
		this.approvals = (await withdrawApproval(this.target(kind, id))).approvals;
		if (this.justApproved === key(kind, id)) this.justApproved = null;
	}

	/** Puts a suggestion returned by the API in the list (replacing an older copy), newest first. */
	keep(s: Suggestion) {
		const rest = this.suggestions.filter((x) => x.id !== s.id);
		this.suggestions = [s, ...rest].sort((a, b) => b.id - a.id);
	}

	async suggest(
		kind: string,
		id: string,
		action: SuggestionAction,
		extra: { edits?: Record<string, string>; furigana?: Record<string, string>; comment?: string } = {}
	): Promise<Suggestion> {
		const hash = this.hashOf(kind, id) ?? '';
		const s = await suggest(this.target(kind, id), hash, action, extra);
		this.keep(s);
		return s;
	}

	async withdraw(id: number) {
		this.keep(await withdrawSuggestion(id));
	}

	async comment(id: number, text: string) {
		this.keep(await comment(id, text));
	}
}
