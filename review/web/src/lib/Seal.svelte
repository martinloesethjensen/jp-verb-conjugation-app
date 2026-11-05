<script lang="ts">
	// The red 確認 seal a reviewer stamps on an item. It presses (a short stamp animation) only when the
	// viewer's own approval has just appeared, never on load, and never with reduced motion.
	import { untrack } from 'svelte';
	import { prefersReducedMotion, shouldPress } from './seal.ts';

	let { name, pressed = false }: { name: string; pressed?: boolean } = $props();

	let press = $state(false);
	let was = untrack(() => pressed);

	// A latch on the prop's history (pressed went false → true), which $derived can't express.
	$effect(() => {
		if (shouldPress(was, pressed, prefersReducedMotion())) press = true;
		was = pressed;
	});
</script>

<span class={["seal", { press }]} title="Approved by {name}">
	<span class="mark" lang="ja">確認</span>
	<span class="name">{name}</span>
</span>

<style>
	.seal {
		display: inline-flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		min-width: 3.4rem;
		padding: 0.15rem 0.45rem 0.2rem;
		border: 2px solid var(--red);
		border-radius: 0.4rem;
		color: var(--red);
		background: color-mix(in srgb, var(--red-soft) 60%, transparent);
		transform: rotate(-4deg);
		line-height: 1.15;
	}

	.mark {
		font-size: 1rem;
		font-weight: 700;
		letter-spacing: 0.1em;
	}

	.name {
		max-width: 6rem;
		overflow: hidden;
		font-size: 0.7rem;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.press {
		animation: seal-press 380ms cubic-bezier(0.2, 0.9, 0.3, 1.2);
	}
</style>
