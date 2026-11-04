// The Worker's API (review/api). Same origin, behind Cloudflare Access: the browser's Access cookie is the
// only credential, so every request just sends same-origin credentials.

export type Role = 'admin' | 'reviewer';
export type Me = { email: string; display_name: string; role: Role };
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
};

export type ItemList = { dataset: Dataset; version: string; items: ItemSummary[] };

export type ItemResponse = {
	dataset: Dataset;
	version: string;
	id: string;
	content_hash: string;
	item: Record<string, unknown>;
};

export type Reference = { readings: Record<string, string>; forms: Record<string, string> };

export const getSnapshot = async () => (await request<{ files: SnapshotFile[] }>('/api/snapshot')).files;

export const listItems = (dataset: Dataset) =>
	request<ItemList>(`/api/items?${new URLSearchParams({ dataset })}`);

export const getItem = (dataset: Dataset, id: string) =>
	request<ItemResponse>(`/api/item?${new URLSearchParams({ dataset, id })}`);

export const getReference = () => request<Reference>('/api/reference');

export const loadFile = (file: DataFileName) => request<SnapshotFile>('/api/admin/snapshot', { file });
