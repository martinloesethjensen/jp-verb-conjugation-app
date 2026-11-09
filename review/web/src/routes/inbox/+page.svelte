<script lang="ts">
	// The inbox, for teachers and the owner: every suggestion as a red-pen correction, grouped by item so counter-suggestions
	// sit side by side. Accepting only marks a suggestion accepted; nothing reaches data/ until export.
	import { onMount } from 'svelte';
	import { comment, decide, getInbox, problem, type Field, type InboxSuggestion } from '#lib/api.ts';
	import ErrorLine from '#lib/ErrorLine.svelte';
	import SuggestForm from '#lib/SuggestForm.svelte';
	import SuggestionCard from '#lib/SuggestionCard.svelte';
	import { DATASET_TITLES, groupTitle } from '#lib/labels.ts';
	import { loadReference } from '#lib/reference.ts';
	import { canDecide, OWN_SUGGESTION_LINE } from '#lib/roles.ts';
	import { getSession } from '#lib/session.ts';
	import { editForm, suggestionHref } from '#lib/targets.ts';
	import type { Dataset } from '#lib/api.ts';

	const { me } = getSession();
	const allowed = canDecide(me().role);

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
		if (!allowed) return;
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
	/** The fields a teacher or the owner edits: an addition's add form, otherwise the change form. */
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

<h1>Suggestions</h1>

{#if !allowed}
	<p class="notice">Only teachers and Martin can open the inbox.</p>
{:else}

<div class="segmented" role="group" aria-label="Which suggestions">
	{#each TABS as [value, label] (value)}
		<button type="button" aria-pressed={status === value} onclick={() => show(value)}
			>{label}{#if value === 'open' && status === 'open' && suggestions?.length}<span class="open-count"
					>{suggestions.length}</span
				>{/if}</button
		>
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
				<span class="on-what"
					>{groupTitle(first).charAt(0).toUpperCase()}{groupTitle(first).slice(1)} on
					<a href={suggestionHref(first)} lang="ja">{first.item_title}</a></span
				>
				<span class="kind"
					>{DATASET_TITLES[first.dataset as Dataset] ?? first.dataset} · {group.items.length}
					{group.items.length === 1 ? 'suggestion' : 'suggestions'}</span
				>
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
							{#if s.mine}
								<p class="hint">{OWN_SUGGESTION_LINE}</p>
							{:else if confirming?.id === s.id}
								<p class="warning">{confirming.warning}</p>
								<button type="button" class="danger" disabled={busy} onclick={() => accept(s)}>Accept and remove</button>
								<button type="button" class="link" onclick={() => (confirming = null)}>Cancel</button>
							{:else}
								<button
									type="button"
									class="primary"
									disabled={busy || ((s.action === 'change' || adding(s)) && (s.stale || s.gone))}
									title={staleChange(s) ? ACCEPT_STALE : undefined}
									onclick={() => accept(s)}>Accept</button
								>
								{#if canEdit(s)}
									<button type="button" aria-expanded={editing === s.id} onclick={() => (editing = editing === s.id ? null : s.id)}
										>Edit then accept</button
									>
								{/if}
								<button type="button" disabled={busy} onclick={() => act(s, () => decide(s.id, 'decline'))}>Decline</button>
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
{/if}

<style>
	h1 {
		margin: 0 0 1.25rem;
	}

	.segmented {
		margin-bottom: 1.75rem;
	}

	.open-count {
		margin-left: 0.4rem;
		color: var(--red);
		font-weight: 700;
	}

	.group {
		max-width: 46rem;
		margin-bottom: 1.5rem;
		padding: 1.25rem 1.5rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	h2 {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		gap: 0.25rem 0.75rem;
		align-items: baseline;
		margin: 0 0 0.5rem;
		font-size: 1.1rem;
		font-weight: 500;
	}

	.on-what {
		overflow-wrap: anywhere;
	}

	.on-what a {
		font-family: var(--mincho);
	}

	@media (max-width: 720px) {
		.group {
			padding: 1rem;
		}
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
