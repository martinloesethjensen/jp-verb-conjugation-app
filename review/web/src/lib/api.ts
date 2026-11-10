// The Worker's API (review/api). Same origin, behind Cloudflare Access: the browser's Access cookie is the
// only credential, so every request just sends same-origin credentials.

export type Role = 'admin' | 'teacher' | 'reviewer';
/** How someone is credited in the public repo. */
export type PublicRole = 'owner' | 'teacher' | 'native';
export type Me = {
	email: string;
	display_name: string;
	role: Role;
	public_role: PublicRole;
	/** Null: credited by role only. */
	public_name: string | null;
};
export type User = Me & { active: boolean };

export class ApiError extends Error {
	status: number;

	constructor(status: number, message: string) {
		super(message);
		this.name = 'ApiError';
		this.status = status;
	}
}

const FALLBACK = 'Something went wrong. Try again in a minute.';

function message(status: number, serverText: unknown): string {
	if (status === 401) return 'Your sign-in has expired. Reload the page to sign in again.';
	if (status === 403) return "This account can't do that. Ask Martin if you think it should.";
	return typeof serverText === 'string' && serverText ? serverText : FALLBACK;
}

async function request<T>(path: string, body?: unknown): Promise<T> {
	const init: RequestInit =
		body === undefined
			? { credentials: 'same-origin', redirect: 'manual' }
			: {
					method: 'POST',
					headers: { 'content-type': 'application/json' },
					body: JSON.stringify(body),
					credentials: 'same-origin',
					redirect: 'manual'
				};
	let response: Response;
	try {
		response = await fetch(path, init);
	} catch {
		throw new ApiError(0, FALLBACK);
	}
	// An expired Access session answers with a redirect to the sign-in page; don't follow it.
	if (response.type === 'opaqueredirect') throw new ApiError(401, message(401, undefined));
	const data = await response.json().catch(() => undefined);
	if (!response.ok) throw new ApiError(response.status, message(response.status, data?.error));
	return data as T;
}

export const getMe = () => request<Me>('/api/me');

export const listUsers = async () => (await request<{ users: User[] }>('/api/admin/users')).users;

export const addUser = (email: string, displayName: string) =>
	request<User>('/api/admin/users', { email, display_name: displayName });

export const setActive = (email: string, active: boolean) =>
	request<User>('/api/admin/users/active', { email, active });

export const setMyName = (displayName: string) =>
	request<Me>('/api/me/name', { display_name: displayName });

/** Null or blank: anonymous, credited by role only. */
export const setPublicName = (publicName: string | null) =>
	request<Me>('/api/me/public-name', { public_name: publicName });

/** Reviewer or teacher; the owner's own role never changes here. */
export const setAccessRole = (email: string, role: 'teacher' | 'reviewer') =>
	request<User>('/api/admin/users/access', { email, role });

export const setPublicRole = (email: string, publicRole: PublicRole) =>
	request<User>('/api/admin/users/role', { email, public_role: publicRole });

// --- Published data ---------------------------------------------------------------------------

/** The datasets reviewers browse. */
export const DATASETS = ['verbs', 'words', 'counters', 'grammar'] as const;
export type Dataset = (typeof DATASETS)[number];

/** Every published file, in the order the admin page loads them (reference files first). */
export const FILES = ['furigana', 'forms', 'words', 'counters', 'grammar', 'verbs'] as const;
export type DataFileName = (typeof FILES)[number];

export type SnapshotFile = {
	name: DataFileName;
	version: string;
	sha256: string;
	git_ref: string | null;
	item_count: number;
	imported_at: string;
	imported_by: string;
};

export type ItemSummary = {
	item_id: string;
	title: string;
	subtitle: string;
	jlpt: string | null;
	parts: number;
	/** Targets (the entry and its parts) with a current approval. */
	approved: number;
	/** Open suggestions on the entry or its parts. */
	open: number;
	/** The entry and its parts: `parts + 1`. */
	targets: number;
};

export type ItemList = { dataset: Dataset; version: string; items: ItemSummary[] };

export type ItemResponse = {
	dataset: Dataset;
	version: string;
	id: string;
	content_hash: string;
	item: Record<string, unknown>;
};

/** A field a reviewer may edit, from the Worker's table (review/api/src/proposal.rs). */
export type Field = {
	name: string;
	input: 'text' | 'long' | 'jlpt' | 'choice' | 'form' | 'kana' | 'slug';
	optional: boolean;
	choices: string[];
	/** What an add form starts with (a new counter's symbol). */
	default?: string | null;
};

export type Reference = {
	readings: Record<string, string>;
	forms: Record<string, string>;
	/** Keyed `"<dataset>/<kind>"`. */
	fields: Record<string, Field[]>;
	/** The fields an add form asks for, keyed `"<dataset>/<kind>"`. */
	add_fields: Record<string, Field[]>;
	/** The kinds a new part may be added to, keyed `"<dataset>/<kind>"` (entries have none). */
	add_parents: Record<string, string[]>;
};

export const getSnapshot = async () => (await request<{ files: SnapshotFile[] }>('/api/snapshot')).files;

export const listItems = (dataset: Dataset) =>
	request<ItemList>(`/api/items?${new URLSearchParams({ dataset })}`);

export const getItem = (dataset: Dataset, id: string) =>
	request<ItemResponse>(`/api/item?${new URLSearchParams({ dataset, id })}`);

export const getReference = () => request<Reference>('/api/reference');

// Loading a file takes several requests (Workers Free allows ~10 ms of CPU each): begin, then each
// slice, then finish, which swaps the new data in at once.
export type LoadStarted = { load_id: string; file: DataFileName; version: string; slices: number };

export const beginLoad = (file: DataFileName) =>
	request<LoadStarted>('/api/admin/snapshot/begin', { file });

export const loadSlice = (loadId: string, slice: number) =>
	request<{ load_id: string; slice: number; rows: number }>('/api/admin/snapshot/slice', {
		load_id: loadId,
		slice
	});

export const finishLoad = (loadId: string) =>
	request<SnapshotFile>('/api/admin/snapshot/finish', { load_id: loadId });

// --- Reviewing ----------------------------------------------------------------------------------

/** One reviewable thing: an entry or a part of one. */
export type Target = { dataset: string; kind: string; id: string };

export type Approval = {
	kind: string;
	item_id: string;
	reviewer_name: string;
	mine: boolean;
	/** False once the item changed after the approval. */
	current: boolean;
	created_at: string;
};

export type Comment = { author_name: string; mine: boolean; body: string; created_at: string };

/** Something that happened in a thread the viewer is part of (review/api `reply_routes.rs`). */
export type Reply = {
	suggestion_id: number;
	what: 'comment' | 'accepted' | 'declined';
	by_name: string;
	at: string;
	/** The comment, cut to 140 characters; empty for a decision. */
	body: string;
	item_title: string;
	dataset: string;
	kind: string;
	item_id: string;
	entry_id: string;
	action: string;
	parent_kind: string | null;
	parent_id: string | null;
	unread: boolean;
};

export const getReplies = () => request<{ unread: number; replies: Reply[] }>('/api/replies');
export const markRead = (ids: number[]) => request<{ unread: number }>('/api/replies/read', { ids });
export const markAllRead = () => request<{ unread: number }>('/api/replies/read', { all: true });

export type SuggestionAction = 'change' | 'delete' | 'note' | 'add';
export type SuggestionStatus = 'open' | 'accepted' | 'declined' | 'withdrawn';

export type Suggestion = {
	id: number;
	action: SuggestionAction;
	dataset: string;
	kind: string;
	item_id: string;
	entry_id: string;
	item_title: string;
	author_name: string;
	mine: boolean;
	status: SuggestionStatus;
	base_hash: string;
	proposed: Record<string, unknown> | null;
	furigana: Record<string, string> | null;
	dropped_blanks: number;
	comment: string;
	admin_edit: Record<string, unknown> | null;
	created_at: string;
	decided_at: string | null;
	/** The item changed since the suggestion was made. */
	stale: boolean;
	/** The item (an addition: the place it goes) is no longer in the loaded data. */
	gone: boolean;
	/** An addition's parent; null otherwise and for a new entry. */
	parent_kind: string | null;
	parent_id: string | null;
	/** An addition whose new item is now in the loaded data. */
	landed: boolean;
	comments: Comment[];
};

export type ReviewPart = { kind: string; item_id: string; content_hash: string };
/** A stamp the owner made, waiting for export. `name` is the reviewer's public name (null: anonymous). */
export type Stamp = {
	id: number;
	dataset: string;
	kind: string;
	item_id: string;
	entry_id: string;
	item_title: string;
	content_hash: string;
	by: PublicRole;
	name: string | null;
	reviewer_name: string;
	created_at: string;
};

export type Review = {
	parts: ReviewPart[];
	approvals: Approval[];
	suggestions: Suggestion[];
	/** For an entry that takes a stamp: the pending stamp, and whether one can be made now. */
	stamp: Stamp | null;
	stampable: boolean;
};

export type QueueSummary = {
	id: number;
	title: string;
	description: string;
	total: number;
	done: number;
	with_suggestion: number;
	archived: boolean;
};

export type QueueItem = {
	dataset: string;
	kind: string;
	item_id: string;
	entry_id: string;
	title: string;
	note: string;
	position: number;
	gone: boolean;
	mine: 'approved' | 'suggested' | 'skipped' | null;
};

export type Queue = { queue: QueueSummary; items: QueueItem[] };

export type QueueFilter = {
	dataset: string;
	kinds: string[];
	jlpt: string[];
	never_approved: boolean;
	ids: string[];
};

export type QueuePreview = { count: number; items: QueueItem[]; unmatched: string[] };

export type InboxSuggestion = Suggestion & {
	/** The target's JSON now, or null when it left the data. */
	current: Record<string, unknown> | null;
	/** Set when accepting removes a whole verb or word. */
	warning?: string;
};

type Edits = { edits?: Record<string, string>; furigana?: Record<string, string> };

const body = (target: Target) => ({ dataset: target.dataset, kind: target.kind, id: target.id });

export const stampEntry = (dataset: string, id: string, kind = 'entry') =>
	request<Stamp>('/api/admin/stamp', { dataset, id, kind });

export const withdrawStamp = (dataset: string, id: string, kind = 'entry') =>
	request<{ withdrawn: boolean }>('/api/admin/stamp/withdraw', { dataset, id, kind });

/** An entry or verb example whose every covered part is approved, with nothing open and no stamp yet. */
export type ReadyEntry = { dataset: string; kind: string; item_id: string; entry_id: string; entry_title: string; title: string };

export const getStampable = async () =>
	(await request<{ entries: ReadyEntry[] }>('/api/admin/stampable')).entries;

/** An accepted suggestion as export carries it (no email: only how its author is credited). */
export type ExportSuggestion = {
	id: number;
	action: SuggestionAction;
	dataset: string;
	kind: string;
	item_id: string;
	entry_id: string;
	parent_kind: string | null;
	parent_id: string | null;
	item_title: string;
	item: Record<string, unknown> | null;
	editable: string[] | null;
	furigana: Record<string, string> | null;
	comment: string;
	credit: { role: PublicRole; name: string | null };
	decided_at: string | null;
};

export type ExportBatch = {
	files: Record<string, string>;
	suggestions: ExportSuggestion[];
	stamps: Stamp[];
};

export const getExport = () => request<ExportBatch>('/api/admin/export');

export const markExported = (suggestions: number[], stamps: number[]) =>
	request<{ suggestions: number; stamps: number }>('/api/admin/exported', { suggestions, stamps });

export const getReview = (dataset: string, id: string) =>
	request<Review>(`/api/review?${new URLSearchParams({ dataset, id })}`);

export const approve = (target: Target, contentHash: string) =>
	request<{ approvals: Approval[] }>('/api/approve', { ...body(target), content_hash: contentHash });

export const withdrawApproval = (target: Target) =>
	request<{ approvals: Approval[] }>('/api/approve/withdraw', body(target));

export const suggest = (
	target: Target,
	baseHash: string,
	action: SuggestionAction,
	extra: Edits & { comment?: string } = {}
) => request<Suggestion>('/api/suggest', { ...body(target), base_hash: baseHash, action, ...extra });

export const withdrawSuggestion = (id: number) => request<Suggestion>('/api/suggest/withdraw', { id });

export const comment = (suggestionId: number, text: string) =>
	request<Suggestion>('/api/comment', { suggestion_id: suggestionId, body: text });

export const listQueues = async () => (await request<{ queues: QueueSummary[] }>('/api/queues')).queues;

export const getQueue = (id: number) => request<Queue>(`/api/queue?${new URLSearchParams({ id: String(id) })}`);

export const skip = (queueId: number, target: Target) =>
	request<Queue>('/api/queue/skip', { queue_id: queueId, ...body(target) });

export const adminQueues = async () =>
	(await request<{ queues: QueueSummary[] }>('/api/admin/queues')).queues;

export const previewQueue = (filter: QueueFilter, idsText: string) =>
	request<QueuePreview>('/api/admin/queues/preview', { filter, ids_text: idsText });

export const createQueue = (title: string, description: string, filter: QueueFilter, idsText = '') =>
	request<Queue>('/api/admin/queues', { title, description, filter, ids_text: idsText });

export const updateQueue = (id: number, title: string, description: string, archived: boolean) =>
	request<Queue>('/api/admin/queues/update', { id, title, description, archived });

export const setQueueNote = (queueId: number, target: Target, note: string) =>
	request<Queue>('/api/admin/queues/note', { queue_id: queueId, ...body(target), note });

export const removeQueueItem = (queueId: number, target: Target) =>
	request<Queue>('/api/admin/queues/remove', { queue_id: queueId, ...body(target) });

export const getInbox = async (status: 'open' | 'accepted' | 'declined' = 'open') =>
	(await request<{ suggestions: InboxSuggestion[] }>(`/api/inbox?${new URLSearchParams({ status })}`))
		.suggestions;

export const decide = (
	id: number,
	decision: 'accept' | 'decline',
	extra: Edits & { reply?: string; confirm?: boolean } = {}
) => request<Suggestion & { warning?: string }>('/api/decide', { id, decision, ...extra });

/** The message to show for a failed request. */
export function problem(error: unknown): string {
	return error instanceof ApiError ? error.message : FALLBACK;
}

/** Whether a failed request means the item changed since the page loaded. */
export function isStale(error: unknown): boolean {
	return error instanceof ApiError && error.status === 409;
}

// --- Adding -------------------------------------------------------------------------------------

export type ParentRef = { kind: string; id: string };

/** Suggests a new part under `parent`, or a new entry when `parent` is null. */
export const addItem = (
	dataset: string,
	kind: string,
	parent: ParentRef | null,
	fields: Record<string, string>,
	extra: { furigana?: Record<string, string>; comment?: string } = {}
) => request<Suggestion>('/api/add', { dataset, kind, ...(parent ? { parent } : {}), fields, ...extra });

/** Suggested new entries in a dataset, newest first. */
export const getAdditions = async (dataset: string) =>
	(await request<{ suggestions: Suggestion[] }>(`/api/additions?${new URLSearchParams({ dataset })}`)).suggestions;
