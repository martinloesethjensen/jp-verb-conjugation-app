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
		onskip,
		onnext
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
		/** Approving stays on the item; "Next item" calls this. */
		onnext?: () => void;
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
	<p class="what">
		<span>{what}<span lang="ja">{owner}</span></span>
		<a {href}>Open the whole entry <span aria-hidden="true">↗</span></a>
	</p>
	{#if item.note}
		<p class="asks">
			<svg class="bubble" viewBox="0 0 20 20" aria-hidden="true"
				><path d="M4 4h12a1.5 1.5 0 0 1 1.5 1.5v7A1.5 1.5 0 0 1 16 14H9l-4 3v-3H4a1.5 1.5 0 0 1-1.5-1.5v-7A1.5 1.5 0 0 1 4 4z" /></svg
			>
			<span><strong>Martin asks:</strong> {item.note}</span>
		</p>
	{/if}
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
			{onnext}
		/>
	{:else}
		<p class="gone">No longer in the data: {item.title}</p>
	{/if}
</article>

<style>
	.review-card {
		padding: 28px 32px;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
		animation: card-in 240ms ease-out;
	}

	.what {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		gap: 0.25rem 1rem;
		margin: 0 0 1rem;
		font-size: 0.9rem;
		color: var(--muted);
	}

	/* A 44px target; the negative margin keeps the row as tall as its text. */
	.what a {
		display: inline-flex;
		align-items: center;
		min-height: 44px;
		margin: -10px 0;
		color: var(--muted);
	}

	.asks {
		display: flex;
		gap: 0.6rem;
		align-items: flex-start;
		margin: 0 0 1rem;
		padding: 0.75rem 1rem;
		background: var(--paper);
		border-radius: var(--radius-input);
	}

	.bubble {
		flex: none;
		width: 20px;
		height: 20px;
		margin-top: 0.15rem;
		fill: none;
		stroke: var(--muted);
		stroke-width: 1.5;
		stroke-linejoin: round;
	}

	@media (max-width: 720px) {
		.review-card {
			padding: 20px;
		}
	}

	.gone {
		color: var(--muted);
	}
</style>
