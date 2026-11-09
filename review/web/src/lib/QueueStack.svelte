<script lang="ts">
	// A queue on the home page: a small stack of paper with its title and progress. The featured one is
	// the wide "Continue" card; `children` can add a preview of the next item to it.
	import type { Snippet } from 'svelte';
	import type { QueueSummary } from './api.ts';
	import Progress from './Progress.svelte';

	let { queue, featured = false, children }: { queue: QueueSummary; featured?: boolean; children?: Snippet } =
		$props();

	const finished = $derived(queue.total > 0 && queue.done >= queue.total);
</script>

<a class={['stack', { featured }]} href="/queue?id={queue.id}">
	<span class="body">
		{#if featured}<span class="eyebrow">Continue</span>{/if}
		<span class="heading">
			<span class="title">{queue.title}</span>
			{#if finished}<span class="seal" lang="ja" aria-hidden="true"><ruby>確認<rt>かくにん</rt></ruby></span>{/if}
		</span>
		{#if queue.description}<span class="description">{queue.description}</span>{/if}
		<span class="count">{finished ? 'All done, thank you' : `${queue.done} of ${queue.total} done`}</span>
		<Progress total={queue.total} done={queue.done} flagged={queue.with_suggestion} />
		{#if featured}<span class="button-look">Continue reviewing <span aria-hidden="true">→</span></span>{/if}
	</span>
	{#if children}{@render children()}{/if}
</a>

<style>
	/* Two sheets peek out from under the top one. */
	.stack {
		position: relative;
		display: grid;
		gap: 1.5rem;
		padding: 1.25rem 1.4rem 1.3rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
		text-decoration: none;
		overflow-wrap: anywhere;
		box-shadow:
			3px 3px 0 -1px var(--card),
			3px 3px 0 0 var(--rule),
			6px 6px 0 -1px var(--card),
			6px 6px 0 0 var(--rule);
	}

	.stack:hover {
		border-color: var(--ink);
	}

	.body {
		display: grid;
		gap: 0.4rem;
		align-content: start;
	}

	.featured {
		grid-template-columns: minmax(0, 1fr) auto;
		padding: 1.75rem 2rem;
	}

	.heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: 0.75rem;
	}

	.title {
		font-size: 1.1rem;
		font-weight: 500;
		line-height: 1.35;
	}

	.featured .title {
		font-size: 24px;
	}

	.seal {
		flex: none;
		padding: 0 0.35rem 0.1rem;
		border: 2px solid var(--red);
		border-radius: 0.4rem;
		color: var(--red);
		background: color-mix(in srgb, var(--red-soft) 60%, transparent);
		font-weight: 700;
		line-height: 1.6;
		transform: rotate(-4deg);
	}

	.seal :global(rt) {
		font-size: 0.5em;
		font-weight: 500;
	}

	.description,
	.count {
		font-size: 0.9rem;
		color: var(--muted);
	}

	/* Looks like the primary button; it is part of the link, never a nested button. */
	.button-look {
		justify-self: start;
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
		min-height: 44px;
		margin-top: 0.75rem;
		padding: 0 1.3rem;
		border-radius: 999px;
		background: var(--ink);
		color: var(--card);
		font-weight: 500;
	}

	@media (max-width: 720px) {
		.featured {
			grid-template-columns: minmax(0, 1fr);
			padding: 1.4rem 1.25rem;
		}

		.featured .title {
			font-size: 1.25rem;
		}
	}
</style>
