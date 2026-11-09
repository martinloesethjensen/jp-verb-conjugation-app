<script lang="ts">
	// The heading of one item's group in the inbox: what it is and where, how many suggestions, and the
	// item as it is now, so the corrections below read against it.
	import type { Dataset, InboxSuggestion } from './api.ts';
	import PartView from './PartView.svelte';
	import { DATASET_TITLES, groupTitle } from './labels.ts';
	import { suggestionHref } from './targets.ts';

	let {
		first,
		count,
		readings,
		forms
	}: { first: InboxSuggestion; count: number; readings: Record<string, string>; forms: Record<string, string> } = $props();

	const title = $derived(groupTitle(first));
	// A whole entry is too big to repeat here; its own page is a link away.
	const showNow = $derived(first.current !== null && first.kind !== 'entry');
</script>

<h2>
	<span class="on-what"
		>{title.charAt(0).toUpperCase()}{title.slice(1)} on <a href={suggestionHref(first)} lang="ja">{first.item_title}</a></span
	>
	<span class="kind">{DATASET_TITLES[first.dataset as Dataset] ?? first.dataset} · {count} {count === 1 ? 'suggestion' : 'suggestions'}</span>
</h2>
{#if showNow && first.current}
	<div class="now">
		<PartView dataset={first.dataset} kind={first.kind} value={first.current} {readings} {forms} />
	</div>
{/if}

<style>
	h2 {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		gap: 0.25rem 0.75rem;
		align-items: baseline;
		margin: 0 0 0.5rem;
		font-size: 1.1rem;
		font-weight: 500;
	}

	.on-what {
		overflow-wrap: anywhere;
	}

	.on-what a {
		font-family: var(--mincho);
	}

	.kind {
		font-size: 0.85rem;
		color: var(--muted);
	}

	.now {
		margin: 0.25rem 0 0.75rem;
		padding: 0 1rem;
		background: var(--paper);
		border-radius: var(--radius-input);
	}
</style>
