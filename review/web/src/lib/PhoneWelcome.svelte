<script lang="ts">
	// The phone's first run: four full-screen cards over Home, with dots and Skip. Either way out ends the tour.
	import { PHONE_CARDS } from './tour.ts';

	let { ondone, start = 0 }: { ondone: () => void; start?: number } = $props();

	// svelte-ignore state_referenced_locally
	let index = $state(start);
	const card = $derived(PHONE_CARDS[index]);
	const last = $derived(index === PHONE_CARDS.length - 1);
</script>

<div class="phone-welcome" role="dialog" aria-modal="true" aria-labelledby="phone-welcome-title">
	<div class="body">
		<h2 id="phone-welcome-title">{card.title}</h2>
		<p>{card.text}</p>
	</div>
	<ol class="dots" aria-label="Card {index + 1} of {PHONE_CARDS.length}">
		{#each PHONE_CARDS as c, i (c.title)}
			<li class="dot" class:on={i === index} aria-current={i === index ? 'step' : undefined}></li>
		{/each}
	</ol>
	<div class="bar">
		<button type="button" class="link" onclick={ondone}>Skip</button>
		{#if last}
			<button type="button" class="primary" onclick={ondone}>Start reviewing</button>
		{:else}
			<button type="button" class="primary" onclick={() => (index += 1)}>Next</button>
		{/if}
	</div>
</div>

<style>
	.phone-welcome {
		position: fixed;
		inset: 0;
		z-index: 70;
		display: flex;
		flex-direction: column;
		padding: 2rem 16px calc(1rem + env(safe-area-inset-bottom));
		background: var(--paper);
	}

	.body {
		flex: 1;
		display: flex;
		flex-direction: column;
		justify-content: center;
	}

	h2 {
		margin: 0 0 1rem;
		font-size: 1.75rem;
		font-weight: 500;
	}

	p {
		margin: 0;
		font-size: 1.1rem;
		line-height: 1.6;
	}

	.dots {
		display: flex;
		justify-content: center;
		gap: 0.5rem;
		margin: 1.5rem 0;
		padding: 0;
		list-style: none;
	}

	.dot {
		width: 0.55rem;
		height: 0.55rem;
		border: 1.5px solid var(--ink);
		border-radius: 999px;
	}

	.dot.on {
		background: var(--ink);
	}

	.bar {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: 1rem;
	}

	.bar button {
		min-height: 48px;
	}

	.bar .primary {
		flex: 1;
	}
</style>
