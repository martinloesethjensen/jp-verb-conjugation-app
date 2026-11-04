<script lang="ts">
	import { onMount } from 'svelte';
	import { ApiError, listItems, type Dataset, type ItemSummary } from './api.ts';
	import Japanese from './Japanese.svelte';
	import LevelPill from './LevelPill.svelte';
	import { DATASET_TITLES } from './labels.ts';
	import { loadReference } from './reference.ts';

	let { dataset }: { dataset: Dataset } = $props();

	const LEVELS = ['N5', 'N4', 'N3', 'N2', 'N1'];

	let items = $state<ItemSummary[] | null>(null);
	let version = $state('');
	let readings = $state<Record<string, string>>({});
	let failure = $state<string | null>(null);
	let search = $state('');
	let level = $state('');

	onMount(() => {
		listItems(dataset)
			.then((list) => {
				items = list.items;
				version = list.version;
			})
			.catch((error) => {
				failure = error instanceof ApiError ? error.message : 'Something went wrong. Try again in a minute.';
			});
		loadReference().then((reference) => (readings = reference.readings));
	});

	const shown = $derived.by(() => {
		const needle = search.trim().toLowerCase();
		return (items ?? []).filter(
			(item) =>
				(!level || item.jlpt === level) &&
				(!needle || `${item.title} ${item.subtitle}`.toLowerCase().includes(needle))
		);
	});

	const href = (item: ItemSummary) => `/item?${new URLSearchParams({ dataset, id: item.item_id })}`;
</script>

<div class="heading">
	<h1>{DATASET_TITLES[dataset]}</h1>
	{#if version}<p class="version">Version {version}</p>{/if}
</div>

{#if failure}
	<p class="notice" role="alert">{failure}</p>
{:else if items === null}
	<p class="quiet">Loading…</p>
{:else}
	<div class="filters">
		<label class="search">
			<span class="visually-hidden">Search</span>
			<input type="search" placeholder="Search" bind:value={search} />
		</label>
		<label>
			<span class="visually-hidden">JLPT level</span>
			<select bind:value={level}>
				<option value="">All levels</option>
				{#each LEVELS as l (l)}<option value={l}>{l}</option>{/each}
			</select>
		</label>
	</div>
	{#if shown.length === 0}
		<p class="quiet">No matches.</p>
	{:else}
		<ul class="items">
			{#each shown as item (item.item_id)}
				<li>
					<a href={href(item)}>
						<span class="title"><Japanese text={item.title} {readings} /></span>
						<span class="meta">
							<LevelPill level={item.jlpt} />
							{#if item.parts}<span class="parts">{item.parts} {item.parts === 1 ? 'part' : 'parts'}</span>{/if}
						</span>
						<span class="subtitle">{item.subtitle}</span>
					</a>
				</li>
			{/each}
		</ul>
	{/if}
{/if}

<style>
	.heading {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: 0.25rem 1rem;
	}

	h1 {
		margin: 0;
		font-size: 1.5rem;
		font-weight: 500;
	}

	.version,
	.quiet,
	.parts,
	.subtitle {
		color: var(--muted);
	}

	.version {
		margin: 0;
		font-size: 0.9rem;
	}

	.filters {
		display: flex;
		flex-wrap: wrap;
		gap: 0.75rem;
		margin: 1.25rem 0;
	}

	.search {
		flex: 1 1 16rem;
	}

	select {
		font: inherit;
		color: inherit;
		padding: 0.45rem 0.6rem;
		border: 1px solid var(--rule);
		border-radius: var(--radius);
		background: var(--card);
	}

	.items {
		margin: 0;
		padding: 0;
		list-style: none;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	.items li + li {
		border-top: 1px solid var(--rule);
	}

	.items a {
		display: grid;
		grid-template-columns: minmax(0, 1fr) auto;
		gap: 0.15rem 1rem;
		padding: 0.75rem 1rem;
		text-decoration: none;
	}

	.items a:hover {
		background: var(--paper);
	}

	.title {
		font-size: 1.1rem;
	}

	.title :global(rt) {
		font-size: 0.55em;
		color: var(--muted);
	}

	.meta {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		font-size: 0.85rem;
	}

	.subtitle {
		grid-column: 1 / -1;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.notice {
		max-width: 34rem;
		padding: 0.75rem 1rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}
</style>
