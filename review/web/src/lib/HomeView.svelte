<script lang="ts">
	// Home: the greeting, the queue to continue, the other queues, and the four datasets to browse.
	import { DATASETS, type QueueItem, type QueueSummary, type SnapshotFile } from './api.ts';
	import { DATASET_JAPANESE, DATASET_TITLES } from './labels.ts';
	import Japanese from './Japanese.svelte';
	import QueueStack from './QueueStack.svelte';

	let {
		name,
		queues,
		files,
		next,
		readings
	}: {
		name: string;
		queues: QueueSummary[];
		/** Null while the snapshot loads; empty when it failed. */
		files: SnapshotFile[] | null;
		/** The featured queue's next item, once loaded. */
		next: QueueItem | undefined;
		readings: Record<string, string>;
	} = $props();

	const featured = $derived(queues.find((q) => q.done < q.total));
	const others = $derived(queues.filter((q) => q !== featured));
	const versionOf = (dataset: string) => files?.find((f) => f.name === dataset)?.version;
</script>

<header class="intro">
	<p class="eyebrow">Waiting for you</p>
	<h1>Hello, {name}.</h1>
	{#if queues.length}
		<p class="lead">
			Martin has {queues.length} {queues.length === 1 ? 'queue' : 'queues'} for you. Pick up where you left off, or
			browse the data.
		</p>
	{/if}
</header>

{#if queues.length}
	<section class="waiting" aria-label="Your queues">
		{#if featured}
			<QueueStack queue={featured} featured>
				{#if next}
					<span class="next">
						<span class="eyebrow">Next up</span>
						<span class="next-title"><Japanese text={next.title} {readings} /></span>
					</span>
				{/if}
			</QueueStack>
		{/if}
		{#if others.length}
			<ul class="queues">
				{#each others as queue (queue.id)}<li><QueueStack {queue} /></li>{/each}
			</ul>
		{/if}
	</section>
{:else}
	<section class="empty card">
		<p class="empty-lead">Nothing is waiting for you yet.</p>
		<p class="quiet">Martin will add things to review here.</p>
	</section>
{/if}

<section class="browse" aria-labelledby="browse-heading">
	<h2 id="browse-heading">Browse the data</h2>
	<ul class="datasets">
		{#each DATASETS as dataset (dataset)}
			<li>
				<a href="/browse/{dataset}">
					<span class="tile" lang="ja"
						><ruby>{DATASET_JAPANESE[dataset].kanji}<rt>{DATASET_JAPANESE[dataset].reading}</rt></ruby></span
					>
					<span class="text">
						<span class="name">{DATASET_TITLES[dataset]}</span>
						<span class="version">
							{#if files === null}&nbsp;{:else if versionOf(dataset)}Version {versionOf(dataset)}{:else}Not loaded yet{/if}
						</span>
					</span>
				</a>
			</li>
		{/each}
	</ul>
</section>

<style>
	.intro {
		margin-bottom: 2rem;
	}

	.intro h1 {
		margin: 0.35rem 0 0.5rem;
		overflow-wrap: anywhere;
	}

	.lead {
		max-width: 40rem;
		margin: 0;
		font-size: 1.1rem;
		color: var(--muted);
	}

	.waiting {
		display: grid;
		gap: 28px;
		margin-bottom: 3rem;
	}

	.queues {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
		gap: 28px;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.empty {
		max-width: 34rem;
		margin-bottom: 3rem;
		padding: 1.5rem;
	}

	.empty p {
		margin: 0;
	}

	.empty-lead {
		font-size: 1.15rem;
		font-weight: 500;
	}

	h2 {
		margin: 0 0 1.25rem;
		padding-bottom: 0.6rem;
		border-bottom: 1px solid var(--rule);
		font-size: 1.15rem;
		font-weight: 700;
	}

	.datasets {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
		gap: 1rem;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.datasets a {
		display: flex;
		align-items: center;
		gap: 1rem;
		height: 100%;
		padding: 1rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
		text-decoration: none;
	}

	.datasets a:hover {
		border-color: var(--ink);
	}

	/* A genkō square holding the Japanese label. */
	.tile {
		display: grid;
		place-items: center;
		flex: none;
		width: 64px;
		height: 56px;
		border: 1px solid color-mix(in srgb, var(--grid) 38%, transparent);
		border-radius: var(--radius-input);
		background:
			linear-gradient(color-mix(in srgb, var(--grid) 38%, transparent), color-mix(in srgb, var(--grid) 38%, transparent))
				center / 100% 1px no-repeat,
			var(--paper);
		font-size: 1rem;
		font-weight: 700;
		line-height: 1.4;
	}

	.tile :global(rt) {
		font-size: 0.5em;
		font-weight: 500;
	}

	.text {
		display: grid;
		min-width: 0;
	}

	.name {
		font-size: 1.05rem;
		font-weight: 500;
	}

	.version {
		font-size: 0.9rem;
		color: var(--muted);
	}

	/* The next item on a strip of genkō paper. Hidden on phones to keep the card short. */
	.next {
		display: grid;
		align-content: center;
		gap: 0.5rem;
		min-width: 14rem;
		max-width: 22rem;
		padding: 1.25rem 1.5rem;
		border-radius: var(--radius-input);
		background:
			repeating-linear-gradient(
				to bottom,
				transparent 0 calc(2.5rem - 1px),
				color-mix(in srgb, var(--grid) 38%, transparent) calc(2.5rem - 1px) 2.5rem
			),
			var(--paper);
	}

	.next-title {
		font-size: 1.6rem;
		line-height: 2.5rem;
	}

	@media (max-width: 720px) {
		.next {
			display: none;
		}

		.datasets {
			grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
		}

		.datasets a {
			flex-direction: column;
			align-items: flex-start;
			gap: 0.6rem;
		}
	}
</style>
