<script lang="ts">
	// The inbox, for teachers, natives and the owner (natives decide only Japanese-only changes): every suggestion as a red-pen correction, grouped by item so counter-suggestions
	// sit side by side. Accepting only marks a suggestion accepted; nothing reaches data/ until export.
	import { onMount } from 'svelte';
	import { cancelOpinion, comment, decide, getInbox, problem, type Field, type InboxSuggestion } from '#lib/api.ts';
	import AskOpinion from '#lib/AskOpinion.svelte';
	import ErrorLine from '#lib/ErrorLine.svelte';
	import SuggestForm from '#lib/SuggestForm.svelte';
	import InboxGroupHeader from '#lib/InboxGroupHeader.svelte';
	import OpinionStatus from '#lib/OpinionStatus.svelte';
	import { disagreement, openChanges } from '#lib/opinions.ts';
	import SuggestionCard from '#lib/SuggestionCard.svelte';
	import Tip from '#lib/Tip.svelte';
	import { DATASET_TITLES, groupTitle } from '#lib/labels.ts';
	import { loadReference } from '#lib/reference.ts';
	import { canAskOpinion, canDecide, editableFields, mayDecide, ownSuggestionLine, TEACHER_DECIDES } from '#lib/roles.ts';
	import { getSession } from '#lib/session.ts';
	import { editForm, suggestionHref } from '#lib/targets.ts';
	import type { Dataset } from '#lib/api.ts';

	const { me } = getSession();
	const allowed = canDecide(me().role);
	const mayAsk = canAskOpinion(me().role);

	type Status = 'open' | 'waiting' | 'accepted' | 'declined';
	const TABS: [Status, string][] = [
		['open', 'Open'],
		['waiting', 'Waiting for an opinion'],
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

	/** The request on a group's item, if any, and whether the group still has open changes to ask about (notes don't count). */
	const opinionOf = (items: InboxSuggestion[]) => items.find((s) => s.opinion)?.opinion ?? null;
	const hasOpen = (items: InboxSuggestion[]) => openChanges(items).length > 0;

	async function cancel(id: number) {
		try {
			await cancelOpinion(id);
			await show(status);
		} catch (error) {
			failure = problem(error);
		}
	}

	const adding = (s: InboxSuggestion) => s.action === 'add';
	/** The target's fields: an addition's add form, otherwise the change form. */
	const fieldsOf = (s: InboxSuggestion) => (adding(s) ? addFields : fieldTable)[`${s.dataset}/${s.kind}`] ?? [];
	/** What Edit then accept offers: a native only the Japanese fields. */
	const editFields = (s: InboxSuggestion) => editableFields(me().role, fieldsOf(s));
	const canEdit = (s: InboxSuggestion) =>
		editFields(s).length > 0 && s.action !== 'delete' && (adding(s) ? !s.gone : !!s.current);
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
	<p class="notice">Only teachers, native speakers who accept Japanese fixes, and Martin can open the inbox.</p>
{:else}
<Tip id="inbox" />

<div class="tabs-scroll">
<div class="segmented" role="group" aria-label="Which suggestions">
	{#each TABS as [value, label] (value)}
		<button type="button" aria-pressed={status === value} onclick={() => show(value)}
			>{label}{#if value === 'open' && status === 'open' && suggestions?.length}<span class="open-count"><span class="visually-hidden">{', '}</span>{suggestions.length}<span class="visually-hidden">{' open'}</span></span>{/if}</button
		>
	{/each}
</div>
</div>

{#if failure}
	<p class="notice" role="alert">{failure}</p>
{:else if suggestions === null}
	<p class="quiet">Loading…</p>
{:else if !suggestions.length}
	<p class="quiet">{status === 'open' ? 'No open suggestions. Everything has been decided.' : status === 'waiting' ? 'Nothing is waiting for an opinion.' : `Nothing ${status} yet.`}</p>
{:else}
	{#each groups as group (group.key)}
		{@const first = group.items[0]}
		{@const opinion = opinionOf(group.items)}
		{@const banner = status === 'declined' || status === 'accepted' ? null : disagreement(group.items)}
		<section class="group">
			<InboxGroupHeader {first} count={group.items.length} {readings} {forms} />
			{#if banner}
				<p class="banner">
					<svg class="swap" viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"
						><path d="M4 8h15m-4-4 4 4-4 4" /><path d="M20 16H5m4-4-4 4 4 4" /></svg
					>
					<span><strong>{banner.slice(0, banner.lastIndexOf('. ') + 1)}</strong> {banner.slice(banner.lastIndexOf('. ') + 2)}</span>
				</p>
			{/if}
			<div class="cards">
			{#each group.items as s (s.id)}
				<div class="item">
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
								<p class="hint">{ownSuggestionLine(me().role)}</p>
							{:else if !mayDecide(me().role, s)}
								<p class="hint">{TEACHER_DECIDES}</p>
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
						fields={editFields(s)}
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
				</div>
			{/each}
			</div>
			{#if opinion && (opinion.waiting || opinion.answered_at)}
				<OpinionStatus {opinion} suggestions={group.items} {readings} oncancel={() => cancel(opinion.id)} />
			{/if}
			{#if mayAsk && hasOpen(group.items) && !opinion?.waiting}
				<AskOpinion
					target={{ dataset: first.dataset, kind: first.kind, id: first.item_id }}
					count={openChanges(group.items).length}
					onasked={() => show(status)}
				/>
			{/if}
		</section>
	{/each}
{/if}
{/if}

<style>
	h1 {
		margin: 0 0 1.25rem;
	}

	/* On a narrow phone the tabs scroll inside their own box rather than widening the page. */
	.tabs-scroll {
		max-width: 100%;
		margin-bottom: 1.75rem;
		overflow-x: auto;
		scrollbar-width: none;
	}

	.segmented {
		white-space: nowrap;
	}

	.open-count {
		margin-left: 0.4rem;
		color: var(--red);
		font-weight: 700;
	}

	.group {
		max-width: 62rem;
		margin-bottom: 1.5rem;
		padding: 1.25rem 1.5rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}




	/* Counter-suggestions side by side when there is room. */
	.cards {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
		gap: 1rem;
		align-items: start;
	}

	.item {
		min-width: 0;
	}

	.banner {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		margin: 0 0 1rem;
		padding: 0.75rem 1rem;
		background: var(--well);
		border-radius: var(--radius);
	}

	.swap {
		flex: none;
	}

	@media (max-width: 720px) {
		.group {
			padding: 1rem;
		}
	}

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
