<script module lang="ts">
	/** The one-time tips, by the id the Worker knows (`TIPS` in review/api/src/store.rs). */
	export const TIP_TEXT: Record<'inbox' | 'thread', string> = {
		inbox:
			'Each suggestion is decided on its own. Edit then accept fixes one before accepting it, and your reply goes to everyone in the thread.',
		thread: 'Reply under a suggestion to talk it through. Its author and everyone who replied are told.'
	};
</script>

<script lang="ts">
	// A one-time hint: shown until "Got it", and never when tips are off in Settings or settings didn't load.
	import { settings } from './settings.svelte.ts';

	let { id, text }: { id: keyof typeof TIP_TEXT | string; text?: string } = $props();
	const shown = $derived(text ?? TIP_TEXT[id as keyof typeof TIP_TEXT] ?? '');
</script>

{#if settings.tipOpen(id) && shown}
	<aside class="tip" aria-label="Tip">
		<p>{shown}</p>
		<button type="button" class="link" onclick={() => settings.change({ dismiss_tip: id }).catch(() => {})}>Got it</button>
	</aside>
{/if}

<style>
	.tip {
		display: flex;
		align-items: center;
		gap: 1rem;
		margin: 0 0 1rem;
		padding: 0.6rem 0.9rem;
		border: 1px solid var(--ink);
		border-radius: var(--radius-input);
		background: var(--card);
	}

	p {
		flex: 1;
		margin: 0;
	}

	button {
		min-height: 44px;
		flex: none;
	}
</style>
