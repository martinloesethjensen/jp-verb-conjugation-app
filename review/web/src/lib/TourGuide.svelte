<script lang="ts">
	// The tour's steps on the queue page: each one outlines its target (a class, never inline styles) above a
	// dimmed page and explains it in a card. Skip, or Done on the closing card, ends the tour.
	import { onDestroy } from 'svelte';
	import { TOUR_CLOSING, type TourStep } from './tour.ts';

	let { steps, ondone }: { steps: TourStep[]; ondone: () => void } = $props();

	let index = $state(0);
	const closing = $derived(index >= steps.length);
	const step = $derived(closing ? TOUR_CLOSING : steps[index]);
	let highlighted: Element | null = null;

	function clear() {
		highlighted?.classList.remove('tour-target');
		highlighted = null;
	}

	$effect(() => {
		clear();
		if (closing) return;
		const el = document.querySelector(`[data-tour="${steps[index].target}"]`);
		if (!el) return;
		el.classList.add('tour-target');
		highlighted = el;
		const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
		el.scrollIntoView({ block: 'center', behavior: still ? 'auto' : 'smooth' });
	});

	onDestroy(clear);

	function finish() {
		clear();
		ondone();
	}
</script>

<div class="tour-dim" aria-hidden="true"></div>
<div class="tour-card" role="dialog" aria-labelledby="tour-title" aria-describedby="tour-text">
	{#if !closing}<p class="count">{index + 1} of {steps.length}</p>{/if}
	<h2 id="tour-title">{step.title}</h2>
	<p id="tour-text">{step.text}</p>
	<div class="actions">
		{#if closing}
			<button type="button" class="primary" onclick={finish}>Done</button>
		{:else}
			<button type="button" disabled={index === 0} onclick={() => (index -= 1)}>Back</button>
			<button type="button" class="primary" onclick={() => (index += 1)}>Next</button>
			<button type="button" class="link" onclick={finish}>Skip</button>
		{/if}
	</div>
</div>

<style>
	.tour-dim {
		position: fixed;
		inset: 0;
		z-index: 40;
		background: rgb(30 38 51 / 0.3);
		pointer-events: none;
	}

	.tour-card {
		position: fixed;
		right: 1.5rem;
		bottom: 1.5rem;
		z-index: 60;
		width: min(22rem, calc(100vw - 2rem));
		padding: 1.25rem;
		background: var(--card);
		border: 1px solid var(--ink);
		border-radius: var(--radius);
		box-shadow: 0 8px 24px rgb(30 38 51 / 0.18);
	}

	.count {
		margin: 0;
		color: var(--muted);
		font-size: 0.85rem;
	}

	h2 {
		margin: 0.25rem 0 0.5rem;
		font-size: 1.2rem;
		font-weight: 500;
	}

	.actions {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		margin-top: 1rem;
	}

	.actions button {
		min-height: 44px;
	}
</style>
