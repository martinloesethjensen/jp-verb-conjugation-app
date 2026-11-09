<script lang="ts">
	// Working through one queue, one item at a time. On a laptop the queue's items sit in a list beside
	// the card. The address is /queue?id=…, read once the page is in the browser.
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { getItem, getQueue, problem, skip, type Dataset, type Field, type Queue, type QueueItem } from '#lib/api.ts';
	import Progress from '#lib/Progress.svelte';
	import ReviewCard from '#lib/ReviewCard.svelte';
	import { filterItems, firstUndone, type ItemFilter } from '#lib/queue-items.ts';
	import { loadReference } from '#lib/reference.ts';
	import { EntryReview } from '#lib/review.svelte.ts';

	type Json = { [key: string]: any };
	type Loaded = { entry: Json | null; review: EntryReview };

	let queueId = 0;
	let data = $state<Queue | null>(null);
	let failure = $state<string | null>(null);
	let selected = $state<string | null>(null);
	let filter = $state<ItemFilter>('all');
	let readings = $state<Record<string, string>>({});
	let forms = $state<Record<string, string>>({});
	let fieldTable = $state<Record<string, Field[]>>({});

	const keyOf = (i: QueueItem) => `${i.dataset}/${i.kind}/${i.item_id}`;
	const current = $derived(
		data ? (data.items.find((i) => keyOf(i) === selected) ?? firstUndone(data.items)) : undefined
	);

	// Entries fetched in this visit, so moving between parts of one entry doesn't fetch it again.
	const entries = new Map<string, Promise<Loaded>>();
	function entryFor(item: QueueItem): Promise<Loaded> {
		const key = `${item.dataset}/${item.entry_id}`;
		let pending = entries.get(key);
		if (!pending) {
			const review = new EntryReview(item.dataset, item.entry_id);
			pending = Promise.all([
				getItem(item.dataset as Dataset, item.entry_id)
					.then((r) => r.item as Json)
					.catch(() => null),
				review.load()
			]).then(([entry]) => ({ entry, review }));
			entries.set(key, pending);
		}
		return pending;
	}

	onMount(() => {
		queueId = Number(page.url.searchParams.get('id'));
		if (!queueId) {
			failure = 'This link is missing which queue to show.';
			return;
		}
		refresh();
		loadReference().then((reference) => {
			readings = reference.readings;
			forms = reference.forms;
			fieldTable = reference.fields;
		});
	});

	async function refresh() {
		try {
			data = await getQueue(queueId);
		} catch (error) {
			failure = problem(error);
		}
	}

	/** After an action the next undone item comes up. */
	async function next() {
		selected = null;
		await refresh();
	}

	async function skipCurrent(item: QueueItem) {
		data = await skip(queueId, { dataset: item.dataset, kind: item.kind, id: item.item_id });
		selected = null;
	}

	const shown = $derived(data ? filterItems(data.items, filter) : []);
	const FILTERS: [ItemFilter, string][] = [
		['all', 'All'],
		['todo', 'To do'],
		['done', 'Done']
	];

	const mark = (i: QueueItem) =>
		i.gone ? 'No longer in the data' : i.mine === 'approved' ? 'Approved' : i.mine === 'suggested' ? 'Suggested' : i.mine === 'skipped' ? 'Skipped' : '';
</script>

<svelte:head>
	<title>{data?.queue.title ?? 'Queue'} · Kotoba Table review</title>
</svelte:head>

{#if failure}
	<p class="notice" role="alert">{failure}</p>
{:else if !data}
	<p class="quiet">Loading…</p>
{:else}
	<header class="queue-header">
		<div class="heading">
			<p class="back">
				<a href="/"
					><svg class="chevron" viewBox="0 0 16 16" aria-hidden="true"><path d="M10 3L5 8l5 5" /></svg>Home</a
				>
			</p>
			<h1>{data.queue.title}</h1>
			{#if data.queue.description}<p class="quiet">{data.queue.description}</p>{/if}
		</div>
		<div class="progress-block">
			<p class="count"><strong>{data.queue.done}</strong> of {data.queue.total} done</p>
			<Progress total={data.queue.total} done={data.queue.done} flagged={data.queue.with_suggestion} />
			{#if data.queue.with_suggestion}
				<p class="flagged"><span class="red-dot" aria-hidden="true"></span>{data.queue.with_suggestion} with suggestions</p>
			{/if}
		</div>
	</header>

	<div class="layout">
		<nav class="list card" aria-label="Items in this queue">
			<div class="filters" role="group" aria-label="Show">
				{#each FILTERS as [value, label] (value)}
					<button type="button" class="chip" aria-pressed={filter === value} onclick={() => (filter = value)}>{label}</button>
				{/each}
			</div>
			{#if shown.length}
				<ol>
					{#each shown as i (keyOf(i))}
						{@const isCurrent = current !== undefined && keyOf(current) === keyOf(i)}
						<li>
							<button
								type="button"
								class={['entry', { current: isCurrent, done: i.mine || i.gone }]}
								aria-current={isCurrent ? 'true' : undefined}
								onclick={() => (selected = keyOf(i))}
							>
								<span class="status" aria-hidden="true">
									{#if i.mine === 'approved'}
										<svg class="approved-icon" viewBox="0 0 16 16"
											><rect x="3" y="3" width="10" height="10" rx="1.5" transform="rotate(-8 8 8)" /><path
												d="M5.5 8.2l1.8 1.8 3.3-3.6"
											/></svg
										>
									{:else if i.mine === 'suggested'}
										<svg class="pencil-icon" viewBox="0 0 16 16"><path d="M10.5 2.5l3 3-8 8H2.5v-3z" /></svg>
									{:else if isCurrent}
										<span class="current-dot"></span>
									{:else if !i.mine && !i.gone}
										<span class="todo-ring"></span>
									{/if}
								</span>
								<span class="title" lang="ja">{i.title}</span>
								<span class="mark">{mark(i)}</span>
							</button>
						</li>
					{/each}
				</ol>
			{:else}
				<p class="empty-filter quiet">
					{filter === 'todo' ? 'Nothing left to do in this queue.' : 'Nothing done in this queue yet.'}
				</p>
			{/if}
		</nav>

		<div class="card-pane">
			{#if current}
				{#key keyOf(current)}
					{#await entryFor(current)}
						<p class="quiet">Loading…</p>
					{:then loaded}
						<ReviewCard
							item={current}
							entry={loaded.entry}
							review={loaded.review}
							fields={fieldTable[`${current.dataset}/${current.kind}`] ?? []}
							{readings}
							{forms}
							onaction={next}
							onskip={() => skipCurrent(current)}
						/>
					{:catch error}
						<p class="notice" role="alert">{problem(error)}</p>
					{/await}
				{/key}
			{:else}
				<section class="finished">
					<p class="lead">That's everything in this queue. Thank you!</p>
					<p><a href="/">Back home</a></p>
				</section>
			{/if}
		</div>
	</div>
{/if}

<style>
	.queue-header {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		align-items: flex-end;
		gap: 1rem 3rem;
		margin-bottom: 2rem;
	}

	.heading {
		flex: 1 1 28rem;
		min-width: 0;
		overflow-wrap: anywhere;
	}

	.back {
		margin: 0 0 0.75rem;
	}

	.back a {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		min-height: 44px;
		color: var(--muted);
		text-decoration: none;
	}

	.back a:hover {
		color: var(--ink);
	}

	.chevron {
		width: 16px;
		height: 16px;
		fill: none;
		stroke: currentColor;
		stroke-width: 1.8;
		stroke-linecap: round;
		stroke-linejoin: round;
	}

	h1 {
		margin: 0;
	}

	.heading .quiet {
		margin: 0.5rem 0 0;
	}

	.progress-block {
		flex: 0 1 16rem;
		display: grid;
		gap: 0.4rem;
	}

	.progress-block p {
		margin: 0;
	}

	.count strong {
		font-size: 1.4rem;
	}

	.flagged {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		font-size: 0.9rem;
		color: var(--muted);
	}

	.red-dot {
		width: 0.5rem;
		height: 0.5rem;
		border-radius: 50%;
		background: var(--red);
	}

	.quiet {
		color: var(--muted);
	}

	.layout {
		display: grid;
		gap: 1.5rem;
		max-width: 46rem;
	}

	/* Phones get the card alone; laptops get the list beside it. */
	.list {
		display: none;
	}

	@media (min-width: 960px) {
		.layout {
			grid-template-columns: 19rem minmax(0, 1fr);
			max-width: none;
			align-items: start;
		}

		.list {
			display: block;
			position: sticky;
			top: 1rem;
			max-height: calc(100vh - 2rem);
			overflow-y: auto;
			padding: 0.75rem;
		}
	}

	.filters {
		display: flex;
		gap: 0.4rem;
		padding: 0.25rem 0.25rem 0.75rem;
	}

	ol {
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.entry {
		display: grid;
		grid-template-columns: 20px minmax(0, 1fr);
		gap: 0 0.6rem;
		align-items: center;
		justify-content: stretch;
		width: 100%;
		min-height: 44px;
		padding: 0.45rem 0.65rem;
		border: none;
		border-radius: var(--radius-input);
		background: none;
		font-weight: 400;
		text-align: left;
	}

	.entry:hover {
		background: var(--paper);
	}

	.entry .title {
		font-family: var(--mincho);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.entry.done .title {
		color: var(--muted);
	}

	.entry.current {
		background: var(--paper);
		box-shadow: inset 0 0 0 1.5px var(--ink);
	}

	.status {
		display: grid;
		place-items: center;
		width: 20px;
		height: 20px;
	}

	.approved-icon,
	.pencil-icon {
		width: 18px;
		height: 18px;
		fill: none;
		stroke-width: 1.6;
		stroke-linecap: round;
		stroke-linejoin: round;
	}

	.approved-icon {
		stroke: var(--red);
	}

	.pencil-icon {
		stroke: var(--muted);
	}

	.current-dot {
		width: 10px;
		height: 10px;
		border-radius: 50%;
		background: var(--ink);
	}

	.todo-ring {
		width: 10px;
		height: 10px;
		border-radius: 50%;
		border: 1.5px solid var(--muted);
	}

	.mark {
		grid-column: 2;
		font-size: 0.8rem;
		color: var(--muted);
	}

	.mark:empty {
		display: none;
	}

	.empty-filter {
		margin: 0;
		padding: 1rem 0.65rem;
	}

	.finished {
		padding: 1.5rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	.lead {
		margin-top: 0;
		font-size: 1.15rem;
		font-weight: 500;
	}

	.notice {
		max-width: 34rem;
		padding: 0.75rem 1rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}
</style>
