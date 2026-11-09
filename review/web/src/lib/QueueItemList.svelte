<script lang="ts">
	// A queue's items with the All / To do / Done chips: beside the card on a laptop, in the Items sheet
	// on a phone.
	import type { QueueItem } from './api.ts';
	import FilterChips from './FilterChips.svelte';
	import { filterItems, keyOf, type ItemFilter } from './queue-items.ts';

	let {
		items,
		currentKey,
		filter = $bindable(),
		onselect
	}: {
		items: QueueItem[];
		currentKey: string | undefined;
		filter: ItemFilter;
		onselect: (item: QueueItem) => void;
	} = $props();

	const shown = $derived(filterItems(items, filter));
	const chips = $derived([
		{ value: 'all', label: 'All' },
		{ value: 'todo', label: 'To do', count: filterItems(items, 'todo').length },
		{ value: 'done', label: 'Done' }
	]);

	const mark = (i: QueueItem) =>
		i.gone ? 'No longer in the data' : i.mine === 'approved' ? 'Approved' : i.mine === 'suggested' ? 'Suggested' : i.mine === 'skipped' ? 'Skipped' : '';
</script>

<div class="filters">
	<FilterChips label="Show" options={chips} bind:value={filter} />
</div>
{#if shown.length}
	<ol>
		{#each shown as i (keyOf(i))}
			{@const isCurrent = currentKey !== undefined && currentKey === keyOf(i)}
			<li>
				<button
					type="button"
					class={['entry', { current: isCurrent, done: i.mine || i.gone }]}
					aria-current={isCurrent ? 'true' : undefined}
					onclick={() => onselect(i)}
				>
					<span class="status" aria-hidden="true">
						{#if i.mine === 'approved'}
							<svg class="approved-icon" viewBox="0 0 16 16"
								><rect x="3" y="3" width="10" height="10" rx="1.5" transform="rotate(-8 8 8)" /><path
									d="M5.5 8.2l1.8 1.8 3.3-3.6"
								/></svg
							>
						{:else if i.mine === 'suggested'}
							<svg class="pencil-icon" viewBox="0 0 16 16"><path d="M10.5 2.5l3 3-8 8H2.5v-3z" /></svg>
						{:else if isCurrent}
							<span class="current-dot"></span>
						{:else if !i.mine && !i.gone}
							<span class="todo-ring"></span>
						{/if}
					</span>
					<span class="title" lang="ja">{i.title}</span>
					<span class="mark">{mark(i)}</span>
				</button>
			</li>
		{/each}
	</ol>
{:else}
	<p class="empty-filter quiet">
		{filter === 'todo' ? 'Nothing left to do in this queue.' : 'Nothing done in this queue yet.'}
	</p>
{/if}

<style>
	.quiet {
		color: var(--muted);
	}

	.filters {
		padding: 0.25rem 0.25rem 0.75rem;
	}

	ol {
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.entry {
		display: grid;
		grid-template-columns: 20px minmax(0, 1fr);
		gap: 0 0.6rem;
		align-items: center;
		justify-content: stretch;
		width: 100%;
		min-height: 44px;
		padding: 0.45rem 0.65rem;
		border: none;
		border-radius: var(--radius-input);
		background: none;
		font-weight: 400;
		text-align: left;
	}

	.entry:hover {
		background: var(--paper);
	}

	.entry .title {
		font-family: var(--mincho);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.entry.done .title {
		color: var(--muted);
	}

	.entry.current {
		background: var(--paper);
		box-shadow: inset 0 0 0 1.5px var(--ink);
	}

	.status {
		display: grid;
		place-items: center;
		width: 20px;
		height: 20px;
	}

	.approved-icon,
	.pencil-icon {
		width: 18px;
		height: 18px;
		fill: none;
		stroke-width: 1.6;
		stroke-linecap: round;
		stroke-linejoin: round;
	}

	.approved-icon {
		stroke: var(--red);
	}

	.pencil-icon {
		stroke: var(--muted);
	}

	.current-dot {
		width: 10px;
		height: 10px;
		border-radius: 50%;
		background: var(--ink);
	}

	.todo-ring {
		width: 10px;
		height: 10px;
		border-radius: 50%;
		border: 1.5px solid var(--muted);
	}

	.mark {
		grid-column: 2;
		font-size: 0.8rem;
		color: var(--muted);
	}

	.mark:empty {
		display: none;
	}

	.empty-filter {
		margin: 0;
		padding: 1rem 0.65rem;
	}
</style>
