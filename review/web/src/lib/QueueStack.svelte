<script lang="ts">
	// A queue on the home page: a small stack of paper with its title and progress.
	import type { QueueSummary } from './api.ts';
	import Progress from './Progress.svelte';

	let { queue }: { queue: QueueSummary } = $props();

	const finished = $derived(queue.total > 0 && queue.done >= queue.total);
</script>

<a class="stack" href="/queue?id={queue.id}">
	<span class="title">{queue.title}</span>
	{#if queue.description}<span class="description">{queue.description}</span>{/if}
	<span class="count">{finished ? 'All done, thank you' : `${queue.done} of ${queue.total} done`}</span>
	<Progress total={queue.total} done={queue.done} flagged={queue.with_suggestion} />
</a>

<style>
	/* Two sheets peek out from under the top one. */
	.stack {
		position: relative;
		display: grid;
		gap: 0.3rem;
		padding: 1rem 1.25rem 1.1rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
		text-decoration: none;
		box-shadow:
			3px 3px 0 -1px var(--card),
			3px 3px 0 0 var(--rule),
			6px 6px 0 -1px var(--card),
			6px 6px 0 0 var(--rule);
	}

	.stack:hover {
		border-color: var(--ink);
	}

	.title {
		font-size: 1.1rem;
		font-weight: 500;
	}

	.description,
	.count {
		font-size: 0.9rem;
		color: var(--muted);
	}
</style>
