<script lang="ts">
	import { onMount } from 'svelte';
	import { DATASETS, getSnapshot, listQueues, type QueueSummary, type SnapshotFile } from '#lib/api.ts';
	import { DATASET_TITLES } from '#lib/labels.ts';
	import QueueStack from '#lib/QueueStack.svelte';

	let files = $state<SnapshotFile[] | null>(null);
	let queues = $state<QueueSummary[]>([]);

	onMount(() => {
		getSnapshot()
			.then((list) => (files = list))
			.catch(() => (files = []));
		listQueues()
			.then((list) => (queues = list))
			.catch(() => (queues = []));
	});

	const versionOf = (dataset: string) => files?.find((f) => f.name === dataset)?.version;
</script>

{#if queues.length}
	<section class="waiting" aria-labelledby="waiting-heading">
		<h1 id="waiting-heading">Waiting for you</h1>
		<ul class="queues">
			{#each queues as queue (queue.id)}<li><QueueStack {queue} /></li>{/each}
		</ul>
	</section>
{:else}
	<section class="empty" aria-labelledby="waiting-heading">
		<h1 id="waiting-heading">Waiting for you</h1>
		<p class="lead">Nothing is waiting for you yet.</p>
		<p>Martin will add things to review here.</p>
	</section>
{/if}

<section aria-labelledby="browse-heading">
	<h2 id="browse-heading">Browse</h2>
	<ul class="datasets">
		{#each DATASETS as dataset (dataset)}
			<li>
				<a href="/browse/{dataset}">
					<span class="name">{DATASET_TITLES[dataset]}</span>
					<span class="version">
						{#if files === null}&nbsp;{:else if versionOf(dataset)}Version {versionOf(dataset)}{:else}Not loaded yet{/if}
					</span>
				</a>
			</li>
		{/each}
	</ul>
</section>

<style>
	h1,
	h2 {
		margin-top: 0;
		font-size: 1.15rem;
		font-weight: 500;
	}

	.empty {
		max-width: 34rem;
		margin-bottom: 2.5rem;
		padding: 1.5rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	.waiting {
		margin-bottom: 2.5rem;
	}

	.queues {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(16rem, 1fr));
		gap: 1.25rem;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.lead {
		font-size: 1.15rem;
		font-weight: 500;
	}

	.empty p:last-child {
		margin-bottom: 0;
		color: var(--muted);
	}

	.datasets {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(12rem, 1fr));
		gap: 1rem;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.datasets a {
		display: grid;
		gap: 0.25rem;
		padding: 1rem 1.25rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
		text-decoration: none;
	}

	.datasets a:hover {
		border-color: var(--ink);
	}

	.name {
		font-size: 1.1rem;
		font-weight: 500;
	}

	.version {
		font-size: 0.9rem;
		color: var(--muted);
	}
</style>
