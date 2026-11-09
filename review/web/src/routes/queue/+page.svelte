<script lang="ts">
	// Working through one queue, one item at a time. On a laptop the queue's items sit in a list beside
	// the card. The address is /queue?id=…, read once the page is in the browser.
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { getItem, getQueue, problem, skip, type Dataset, type Field, type Queue, type QueueItem } from '#lib/api.ts';
	import Progress from '#lib/Progress.svelte';
	import ReviewCard from '#lib/ReviewCard.svelte';
	import { firstUndone } from '#lib/queue-items.ts';
	import { loadReference } from '#lib/reference.ts';
	import { EntryReview } from '#lib/review.svelte.ts';

	type Json = { [key: string]: any };
	type Loaded = { entry: Json | null; review: EntryReview };

	let queueId = 0;
	let data = $state<Queue | null>(null);
	let failure = $state<string | null>(null);
	let selected = $state<string | null>(null);
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
		<p class="back"><a href="/">Home</a></p>
		<h1>{data.queue.title}</h1>
		{#if data.queue.description}<p class="quiet">{data.queue.description}</p>{/if}
		<p class="count">{data.queue.done} of {data.queue.total} done</p>
		<Progress total={data.queue.total} done={data.queue.done} flagged={data.queue.with_suggestion} />
	</header>

	<div class="layout">
		<nav class="list" aria-label="Items in this queue">
			<ol>
				{#each data.items as i (keyOf(i))}
					<li>
						<button
							type="button"
							class={['entry', { current: current && keyOf(current) === keyOf(i), done: i.mine || i.gone }]}
							aria-current={current && keyOf(current) === keyOf(i) ? 'true' : undefined}
							onclick={() => (selected = keyOf(i))}
						>
							<span class="title" lang="ja">{i.title}</span>
							{#if i.mine === 'approved'}<span class="dot" aria-hidden="true"></span>{/if}
							<span class="mark">{mark(i)}</span>
						</button>
					</li>
				{/each}
			</ol>
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
		max-width: 42rem;
		margin-bottom: 1.25rem;
	}

	.back {
		margin: 0 0 0.5rem;
	}

	h1 {
		margin: 0;
		font-size: 1.5rem;
		font-weight: 500;
	}

	.count {
		margin: 0.5rem 0 0.35rem;
		font-size: 0.9rem;
	}

	.quiet {
		color: var(--muted);
	}

	.layout {
		display: grid;
		gap: 1.5rem;
		max-width: 42rem;
	}

	/* Phones get the card alone; laptops get the list beside it. */
	.list {
		display: none;
	}

	@media (min-width: 960px) {
		.layout {
			grid-template-columns: 17rem minmax(0, 42rem);
			max-width: none;
			align-items: start;
		}

		.list {
			display: block;
			position: sticky;
			top: 1rem;
			max-height: calc(100vh - 2rem);
			overflow-y: auto;
		}
	}

	ol {
		margin: 0;
		padding: 0;
		list-style: none;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	li + li {
		border-top: 1px solid var(--rule);
	}

	.entry {
		display: grid;
		grid-template-columns: minmax(0, 1fr) auto;
		gap: 0 0.5rem;
		align-items: center;
		width: 100%;
		padding: 0.5rem 0.75rem;
		border: none;
		border-radius: 0;
		background: none;
		text-align: left;
	}

	.entry .title {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.entry.done .title {
		color: var(--muted);
	}

	.entry.current {
		background: var(--paper);
		box-shadow: inset 3px 0 0 var(--ink);
	}

	.dot {
		width: 0.5rem;
		height: 0.5rem;
		border-radius: 50%;
		background: var(--red);
	}

	.mark {
		grid-column: 1 / -1;
		font-size: 0.8rem;
		color: var(--muted);
	}

	.mark:empty {
		display: none;
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
