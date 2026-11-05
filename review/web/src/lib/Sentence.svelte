<script lang="ts">
	import Japanese from './Japanese.svelte';

	let {
		jp,
		en,
		readings,
		extra = {},
		label,
		id
	}: {
		jp: string;
		en: string;
		readings: Record<string, string>;
		extra?: Record<string, string>;
		label?: string;
		id?: string;
	} = $props();
</script>

<div class="sentence" {id}>
	<p class="jp"><Japanese text={jp} {readings} {extra} /></p>
	<p class="en">{en}</p>
	{#if label}<p class="label">{label}</p>{/if}
</div>

<style>
	.sentence {
		padding: 0.75rem 0;
	}

	.sentence + :global(.sentence) {
		border-top: 1px solid var(--rule);
	}

	p {
		margin: 0;
	}

	/* The sentence sits on a faint genkō (manuscript) grid, like a page being marked. */
	.jp {
		font-size: 1.35rem;
		line-height: 2.4;
		background-image:
			linear-gradient(to right, color-mix(in srgb, var(--grid) 22%, transparent) 1px, transparent 1px),
			linear-gradient(to bottom, color-mix(in srgb, var(--grid) 22%, transparent) 1px, transparent 1px);
		background-size: 1.6em 1.6em;
		background-position: 0 0.4em;
	}

	.jp :global(rt) {
		font-size: 0.5em;
		color: var(--muted);
	}

	.en {
		color: var(--ink);
	}

	.label {
		margin-top: 0.25rem;
		font-size: 0.85rem;
		color: var(--muted);
	}
</style>
