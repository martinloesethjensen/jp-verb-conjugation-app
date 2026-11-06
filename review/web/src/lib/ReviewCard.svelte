<script lang="ts">
	// One queued item, reviewed on its own: what it is, the item itself, the owner's question, and the
	// review actions, with everyone else's approvals and suggestions under it.
	import type { Field, QueueItem } from './api.ts';
	import PartView from './PartView.svelte';
	import ReviewBar from './ReviewBar.svelte';
	import { KINDS } from './labels.ts';
	import type { EntryReview } from './review.svelte.ts';
	import { entryTitle, partOf } from './targets.ts';

	type Json = { [key: string]: any };

	let {
		item,
		entry,
		review,
		fields,
		readings,
		forms,
		onaction,
		onskip
	}: {
		item: QueueItem;
		/** The item's entry, or null when it left the data. */
		entry: Json | null;
		review: EntryReview;
		fields: Field[];
		readings: Record<string, string>;
		forms: Record<string, string>;
		onaction: () => void;
		onskip: () => Promise<void>;
	} = $props();

	const value = $derived(entry ? partOf(entry, item.kind, item.item_id) : undefined);
	const owner = $derived(entry ? entryTitle(item.dataset, entry) : item.title);
	const what = $derived.by(() => {
		if (item.kind === 'entry') return '';
		const kind = KINDS[item.kind] ?? item.kind;
		return `${kind.charAt(0).toUpperCase()}${kind.slice(1)} on `;
	});
	const href = $derived(
		`/item?${new URLSearchParams({ dataset: item.dataset, id: item.entry_id })}${item.kind === 'entry' ? '' : `#${item.item_id}`}`
	);
</script>

<article class="review-card">
	<p class="what">{what}<span lang="ja">{owner}</span> · <a {href}>Open the whole entry</a></p>
	{#if item.note}<p class="asks">Martin asks: {item.note}</p>{/if}
	{#if value}
		<PartView dataset={item.dataset} kind={item.kind} {value} {readings} {forms} />
		<ReviewBar
			{review}
			kind={item.kind}
			id={item.item_id}
			{value}
			{fields}
			{readings}
			{forms}
			extra={value.readings ?? {}}
			{onaction}
			{onskip}
		/>
	{:else}
		<p class="gone">No longer in the data: {item.title}</p>
	{/if}
</article>

<style>
	.review-card {
		padding: 1.25rem 1.5rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
		animation: card-in 240ms ease-out;
	}

	.what {
		margin: 0 0 0.75rem;
		font-size: 0.9rem;
		color: var(--muted);
	}

	.what a {
		color: var(--muted);
	}

	.asks {
		margin: 0 0 0.75rem;
		padding: 0.5rem 0.75rem;
		background: var(--paper);
		border-radius: var(--radius);
	}

	.gone {
		color: var(--muted);
	}
</style>
