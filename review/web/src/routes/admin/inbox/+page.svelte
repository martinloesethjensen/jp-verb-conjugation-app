<script lang="ts">
	// The owner's inbox: every suggestion as a red-pen correction, grouped by item so counter-suggestions
	// sit side by side. Accepting only marks a suggestion accepted; nothing reaches data/ until export.
	import { onMount } from 'svelte';
	import { comment, decide, getInbox, problem, type Field, type InboxSuggestion } from '#lib/api.ts';
	import ErrorLine from '#lib/ErrorLine.svelte';
	import SuggestForm from '#lib/SuggestForm.svelte';
	import SuggestionCard from '#lib/SuggestionCard.svelte';
	import { DATASET_TITLES, groupTitle } from '#lib/labels.ts';
	import { loadReference } from '#lib/reference.ts';
	import { editForm, suggestionHref } from '#lib/targets.ts';
	import type { Dataset } from '#lib/api.ts';

	type Status = 'open' | 'accepted' | 'declined';
	const TABS: [Status, string][] = [
		['open', 'Open'],
		['accepted', 'Accepted'],
		['declined', 'Declined']
	];
	const ACCEPT_STALE = 'the data changed since this was suggested; use Edit then accept';

	let status = $state<Status>('open');
	let suggestions = $state<InboxSuggestion[] | null>(null);
	let failure = $state<string | null>(null);
	let readings = $state<Record<string, string>>({});
	let forms = $state<Record<string, string>>({});
	let fieldTable = $state<Record<string, Field[]>>({});
	let addFields = $state<Record<string, Field[]>>({});
	let editing = $state<number | null>(null);
	/** A whole verb or word removal waiting for "Accept and remove": its id and the warning. */
	let confirming = $state<{ id: number; warning: string } | null>(null);
	let actionError = $state<{ id: number; message: string } | null>(null);
	let busy = $state(false);

	onMount(() => {
		show('open');
		loadReference().then((reference) => {
			readings = reference.readings;
			forms = reference.forms;
			fieldTable = reference.fields;
			addFields = reference.add_fields;
		});
	});

	async function show(next: Status) {
		status = next;
		suggestions = null;
		failure = null;
		try {
			suggestions = await getInbox(next);
		} catch (error) {
			failure = problem(error);
		}
	}

	const groups = $derived.by(() => {
		const out: { key: string; items: InboxSuggestion[] }[] = [];
		for (const s of suggestions ?? []) {
			const key = `${s.dataset}/${s.kind}/${s.item_id}`;
			const group = out.find((g) => g.key === key);
			if (group) group.items.push(s);
			else out.push({ key, items: [s] });
		}
		return out;
	});

	const adding = (s: InboxSuggestion) => s.action === 'add';
	/** The fields the owner edits: an addition's add form, otherwise the change form. */
	const fieldsOf = (s: InboxSuggestion) => (adding(s) ? addFields : fieldTable)[`${s.dataset}/${s.kind}`] ?? [];
	const canEdit = (s: InboxSuggestion) =>
		fieldsOf(s).length > 0 && s.action !== 'delete' && (adding(s) ? !s.gone : !!s.current);
	const wholeRemoval = (s: InboxSuggestion) =>
		s.action === 'delete' && s.kind === 'entry' && (s.dataset === 'verbs' || s.dataset === 'words');
	const staleChange = (s: InboxSuggestion) => s.action === 'change' && s.stale;

	async function act(s: InboxSuggestion, action: () => Promise<unknown>) {
		busy = true;
		actionError = null;
		try {
			await action();
			editing = null;
			confirming = null;
			await show(status);
		} catch (error) {
			actionError = { id: s.id, message: problem(error) };
		} finally {
			busy = false;
		}
	}

	async function accept(s: InboxSuggestion) {
		if (wholeRemoval(s) && confirming?.id !== s.id) {
			// The Worker answers with the warning; show it before anything is accepted.
			try {
				await decide(s.id, 'accept');
			} catch (error) {
				confirming = { id: s.id, warning: problem(error) };
				return;
			}
			return show(status);
		}
		await act(s, () => decide(s.id, 'accept', { confirm: wholeRemoval(s) }));
	}

	async function reply(s: InboxSuggestion, text: string) {
		await comment(s.id, text);
		await show(status);
	}
</script>

<svelte:head>
	<title>Suggestions · Kotoba Table review</title>
</svelte:head>

<p class="back"><a href="/admin">Back to admin</a></p>
<h1>Suggestions</h1>

<div class="tabs" role="group" aria-label="Which suggestions">
	{#each TABS as [value, label] (value)}
		<button type="button" class={{ on: status === value }} aria-pressed={status === value} onclick={() => show(value)}>{label}</button>
	{/each}
</div>

{#if failure}
	<p class="notice" role="alert">{failure}</p>
{:else if suggestions === null}
	<p class="quiet">Loading…</p>
{:else if !suggestions.length}
	<p class="quiet">{status === 'open' ? 'No open suggestions. Everything has been decided.' : `Nothing ${status} yet.`}</p>
{:else}
	{#each groups as group (group.key)}
		{@const first = group.items[0]}
		<section class="group">
			<h2>
				<a href={suggestionHref(first)} lang="ja">{first.item_title}</a>
				<span class="kind">{groupTitle(first)} · {DATASET_TITLES[first.dataset as Dataset] ?? first.dataset}</span>
			</h2>
			{#each group.items as s (s.id)}
				<SuggestionCard
					suggestion={s}
					current={s.current}
					names={fieldsOf(s).map((f) => f.name)}
					{readings}
					{forms}
					oncomment={(text) => reply(s, text)}
				>
					{#snippet actions()}
						{#if s.status === 'open'}
							{#if confirming?.id === s.id}
								<p class="warning">{confirming.warning}</p>
								<button type="button" class="danger small" disabled={busy} onclick={() => accept(s)}>Accept and remove</button>
								<button type="button" class="link" onclick={() => (confirming = null)}>Cancel</button>
							{:else}
								<button
									type="button"
									class="primary small"
									disabled={busy || ((s.action === 'change' || adding(s)) && (s.stale || s.gone))}
									title={staleChange(s) ? ACCEPT_STALE : undefined}
									onclick={() => accept(s)}>Accept</button
								>
								{#if canEdit(s)}
									<button type="button" class="small" aria-expanded={editing === s.id} onclick={() => (editing = editing === s.id ? null : s.id)}
										>Edit then accept</button
									>
								{/if}
								<button type="button" class="small" disabled={busy} onclick={() => act(s, () => decide(s.id, 'decline'))}>Decline</button>
								{#if staleChange(s)}<span class="hint">{ACCEPT_STALE}</span>{/if}
							{/if}
						{/if}
					{/snippet}
				</SuggestionCard>
				{#if editing === s.id && canEdit(s)}
					<SuggestForm
						fields={fieldsOf(s)}
						current={editForm(s).base}
						initial={editForm(s).start}
						{readings}
						{forms}
						extra={{ ...((s.current?.readings as Record<string, string> | undefined) ?? {}), ...(s.furigana ?? {}) }}
						submitLabel="Accept with these edits"
						onsubmit={async (edits, furigana) => {
							await decide(s.id, 'accept', {
								edits,
								furigana: Object.keys(furigana).length ? furigana : undefined,
								confirm: wholeRemoval(s)
							});
							editing = null;
							await show(status);
						}}
						oncancel={() => (editing = null)}
					/>
				{/if}
				{#if actionError?.id === s.id}<ErrorLine message={actionError.message} />{/if}
			{/each}
		</section>
	{/each}
{/if}

<style>
	.back {
		margin: 0 0 1rem;
	}

	h1 {
		margin: 0 0 1rem;
		font-size: 1.5rem;
		font-weight: 500;
	}

	.tabs {
		display: flex;
		gap: 0.5rem;
		margin-bottom: 1.25rem;
	}

	.tabs .on {
		background: var(--ink);
		color: var(--card);
	}

	.group {
		max-width: 42rem;
		margin-bottom: 1.25rem;
		padding: 1rem 1.25rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	h2 {
		display: flex;
		flex-wrap: wrap;
		gap: 0.25rem 0.75rem;
		align-items: baseline;
		margin: 0;
		font-size: 1.1rem;
		font-weight: 500;
	}

	.kind,
	.hint,
	.quiet {
		font-size: 0.85rem;
		color: var(--muted);
	}

	.warning {
		flex-basis: 100%;
		margin: 0;
		color: var(--red);
	}

	.notice {
		max-width: 34rem;
		padding: 0.75rem 1rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}
</style>
