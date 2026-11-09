<script lang="ts">
	// The owner's queue builder: pick items by dataset, kind, level and whether anyone approved them, or
	// paste ids; preview; create. Below, the existing queues with their progress and per-item questions.
	import { onMount } from 'svelte';
	import {
		adminQueues,
		createQueue,
		DATASETS,
		getQueue,
		previewQueue,
		problem,
		removeQueueItem,
		setQueueNote,
		updateQueue,
		type Dataset,
		type Queue,
		type QueuePreview,
		type QueueSummary
	} from '#lib/api.ts';
	import ErrorLine from '#lib/ErrorLine.svelte';
	import Progress from '#lib/Progress.svelte';
	import { DATASET_KINDS, DATASET_TITLES, KIND_PLURALS } from '#lib/labels.ts';

	const LEVELS = ['N5', 'N4', 'N3', 'N2', 'N1'];
	const uid = $props.id();

	let title = $state('');
	let description = $state('');
	let dataset = $state<Dataset>('verbs');
	let kinds = $state<string[]>([]);
	let jlpt = $state<string[]>([]);
	let neverApproved = $state(false);
	let idsText = $state('');
	let preview = $state<QueuePreview | null>(null);
	let busy = $state(false);
	let formError = $state<string | null>(null);
	let created = $state<string | null>(null);

	let queues = $state<QueueSummary[] | null>(null);
	let listError = $state<string | null>(null);
	let open = $state<Queue | null>(null);
	let editingId = $state<number | null>(null);
	let editTitle = $state('');
	let editDescription = $state('');
	let notes = $state<Record<string, string>>({});
	let itemError = $state<string | null>(null);

	const filter = () => ({ dataset, kinds, jlpt, never_approved: neverApproved, ids: [] });
	const keyOf = (i: { dataset: string; kind: string; item_id: string }) => `${i.dataset}/${i.kind}/${i.item_id}`;

	onMount(refresh);

	async function refresh() {
		try {
			queues = await adminQueues();
		} catch (error) {
			listError = problem(error);
		}
	}

	async function run(action: () => Promise<void>) {
		busy = true;
		formError = null;
		try {
			await action();
		} catch (error) {
			formError = problem(error);
		} finally {
			busy = false;
		}
	}

	function changeDataset() {
		kinds = kinds.filter((k) => DATASET_KINDS[dataset].includes(k));
		preview = null;
	}

	const showPreview = () => run(async () => void (preview = await previewQueue(filter(), idsText)));

	function create(event: SubmitEvent) {
		event.preventDefault();
		run(async () => {
			const queue = await createQueue(title, description, filter(), idsText);
			created = `Created “${queue.queue.title}” with ${queue.queue.total} items.`;
			title = description = idsText = '';
			preview = null;
			await refresh();
		});
	}

	async function toggle(id: number) {
		if (open?.queue.id === id) {
			open = null;
			return;
		}
		itemError = null;
		try {
			open = await getQueue(id);
			notes = Object.fromEntries(open.items.map((i) => [keyOf(i), i.note]));
		} catch (error) {
			itemError = problem(error);
		}
	}

	async function itemAction(action: () => Promise<Queue>) {
		itemError = null;
		try {
			open = await action();
			await refresh();
		} catch (error) {
			itemError = problem(error);
		}
	}

	function startEdit(q: QueueSummary) {
		editingId = q.id;
		editTitle = q.title;
		editDescription = q.description;
	}

	async function saveQueue(q: QueueSummary, archived = q.archived, newTitle = q.title, newDescription = q.description) {
		listError = null;
		try {
			await updateQueue(q.id, newTitle, newDescription, archived);
			editingId = null;
			await refresh();
		} catch (error) {
			listError = problem(error);
		}
	}
</script>

<svelte:head>
	<title>Queues · Kotoba Table review</title>
</svelte:head>

<p class="back"><a href="/admin">Back to admin</a></p>
<h1>Queues</h1>

<form class="card builder" onsubmit={create}>
	<h2>New queue</h2>
	<label for="{uid}-title">Title</label>
	<input id="{uid}-title" maxlength="80" bind:value={title} />
	<label for="{uid}-description">Description (optional)</label>
	<textarea id="{uid}-description" rows="2" maxlength="2000" bind:value={description}></textarea>

	<label for="{uid}-dataset">Dataset</label>
	<select id="{uid}-dataset" bind:value={dataset} onchange={changeDataset}>
		{#each DATASETS as d (d)}<option value={d}>{DATASET_TITLES[d]}</option>{/each}
	</select>

	<fieldset>
		<legend>Kinds (none ticked: all)</legend>
		{#each DATASET_KINDS[dataset] as kind (kind)}
			<label class="check"><input type="checkbox" value={kind} bind:group={kinds} /> {KIND_PLURALS[kind]}</label>
		{/each}
	</fieldset>
	<fieldset>
		<legend>JLPT levels (none ticked: all)</legend>
		{#each LEVELS as level (level)}
			<label class="check"><input type="checkbox" value={level} bind:group={jlpt} /> {level}</label>
		{/each}
	</fieldset>
	<label class="check"><input type="checkbox" bind:checked={neverApproved} /> Never approved</label>

	<label for="{uid}-ids">Paste ids (optional, one per line)</label>
	<textarea id="{uid}-ids" rows="3" bind:value={idsText}></textarea>

	<div class="buttons">
		<button type="button" disabled={busy} onclick={showPreview}>Preview</button>
		<button class="primary" disabled={busy || !title.trim()}>Create queue</button>
	</div>
	<ErrorLine message={formError} />
	{#if created}<p class="done" role="status">{created}</p>{/if}

	{#if preview}
		<div class="preview" aria-label="Preview">
			<p><strong>{preview.count}</strong> {preview.count === 1 ? 'item matches' : 'items match'}{preview.count > 500 ? '; a queue holds at most 500' : ''}.</p>
			{#if preview.unmatched.length}
				<p class="warning">No match for: <span lang="ja">{preview.unmatched.join(', ')}</span></p>
			{/if}
			<ol>
				{#each preview.items as i (keyOf(i))}<li lang="ja">{i.title}</li>{/each}
			</ol>
			{#if preview.count > preview.items.length}<p class="quiet">and {preview.count - preview.items.length} more</p>{/if}
		</div>
	{/if}
</form>

<section class="existing" aria-labelledby="{uid}-existing">
	<h2 id="{uid}-existing">Existing queues</h2>
	<ErrorLine message={listError} />
	{#if queues === null}
		<p class="quiet">Loading…</p>
	{:else if !queues.length}
		<p class="quiet">No queues yet.</p>
	{:else}
		{#each queues as q (q.id)}
			<article class={['card', 'queue', { archived: q.archived }]}>
				{#if editingId === q.id}
					<label for="{uid}-edit-title-{q.id}">Title</label>
					<input id="{uid}-edit-title-{q.id}" maxlength="80" bind:value={editTitle} />
					<label for="{uid}-edit-description-{q.id}">Description</label>
					<textarea id="{uid}-edit-description-{q.id}" rows="2" bind:value={editDescription}></textarea>
					<div class="buttons">
						<button type="button" class="primary small" onclick={() => saveQueue(q, q.archived, editTitle, editDescription)}>Save</button>
						<button type="button" class="link" onclick={() => (editingId = null)}>Cancel</button>
					</div>
				{:else}
					<h3>{q.title}{#if q.archived} <span class="quiet">(archived)</span>{/if}</h3>
					{#if q.description}<p class="quiet">{q.description}</p>{/if}
				{/if}
				<p class="count">{q.total} items; {q.with_suggestion} with an open suggestion</p>
				<Progress total={q.total} done={q.done} flagged={q.with_suggestion} />
				<div class="buttons">
					<button type="button" class="small" aria-expanded={open?.queue.id === q.id} onclick={() => toggle(q.id)}>
						{open?.queue.id === q.id ? 'Hide items' : 'Show items'}
					</button>
					<button type="button" class="link" onclick={() => startEdit(q)}>Edit</button>
					<button type="button" class="link" onclick={() => saveQueue(q, !q.archived)}>{q.archived ? 'Unarchive' : 'Archive'}</button>
				</div>
				{#if open?.queue.id === q.id}
					<ErrorLine message={itemError} />
					<ol class="items">
						{#each open.items as i (keyOf(i))}
							{@const target = { dataset: i.dataset, kind: i.kind, id: i.item_id }}
							<li>
								<span class="title" lang="ja">{i.title}</span>
								{#if i.gone}<span class="quiet">No longer in the data</span>{/if}
								<form
									class="note"
									onsubmit={(event) => {
										event.preventDefault();
										itemAction(() => setQueueNote(q.id, target, notes[keyOf(i)] ?? ''));
									}}
								>
									<label class="visually-hidden" for="{uid}-note-{keyOf(i)}">Your question for reviewers</label>
									<input id="{uid}-note-{keyOf(i)}" placeholder="Your question for reviewers" maxlength="2000" bind:value={notes[keyOf(i)]} />
									<button class="small">Save</button>
									<button type="button" class="link" onclick={() => itemAction(() => removeQueueItem(q.id, target))}>Remove</button>
								</form>
							</li>
						{/each}
					</ol>
				{/if}
			</article>
		{/each}
	{/if}
</section>

<style>
	.back {
		margin: 0 0 1rem;
	}

	h1 {
		margin: 0 0 1rem;
		font-weight: 500;
	}

	h2 {
		margin: 0 0 0.75rem;
		font-size: 1.15rem;
		font-weight: 500;
	}

	h3 {
		margin: 0;
		font-size: 1.05rem;
		font-weight: 500;
	}

	.card {
		max-width: 42rem;
		margin-bottom: 1.25rem;
		padding: 1.25rem 1.5rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	.builder {
		display: grid;
		gap: 0.35rem;
	}

	label {
		margin-top: 0.4rem;
		font-size: 0.9rem;
	}

	fieldset {
		display: flex;
		flex-wrap: wrap;
		gap: 0.25rem 1rem;
		margin: 0.5rem 0 0;
		padding: 0.5rem 0.75rem;
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	legend {
		font-size: 0.9rem;
	}

	.check {
		display: inline-flex;
		gap: 0.4rem;
		align-items: center;
		margin: 0;
	}

	.check input {
		width: auto;
	}

	.buttons {
		display: flex;
		flex-wrap: wrap;
		gap: 0.5rem 0.75rem;
		align-items: center;
		margin-top: 0.6rem;
	}

	.preview {
		margin-top: 0.75rem;
		padding: 0.75rem 1rem;
		background: var(--paper);
		border-radius: var(--radius);
	}

	.preview p {
		margin: 0 0 0.4rem;
	}

	.preview ol {
		margin: 0;
		padding-left: 1.5rem;
		columns: 2 14rem;
	}

	.quiet,
	.count {
		color: var(--muted);
		font-size: 0.9rem;
	}

	.count {
		margin: 0.5rem 0 0.35rem;
	}

	.warning {
		color: var(--red);
	}

	.done {
		color: var(--green);
	}

	.archived {
		opacity: 0.7;
	}

	.items {
		margin: 0.75rem 0 0;
		padding: 0;
		list-style: none;
	}

	.items li {
		display: grid;
		gap: 0.25rem;
		padding: 0.5rem 0;
		border-top: 1px solid var(--rule);
	}

	.note {
		display: flex;
		flex-wrap: wrap;
		gap: 0.5rem;
		align-items: center;
	}

	.note input {
		flex: 1 1 14rem;
	}

	.visually-hidden {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
	}
</style>
