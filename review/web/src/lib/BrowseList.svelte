<script lang="ts">
	import { onMount } from 'svelte';
	import {
		ApiError,
		comment,
		getAdditions,
		listItems,
		withdrawSuggestion,
		type Dataset,
		type ItemSummary,
		type Suggestion
	} from './api.ts';
	import SuggestionCard from './SuggestionCard.svelte';
	import FilterChips from './FilterChips.svelte';
	import { browseFilter } from './browse.ts';
	import Japanese from './Japanese.svelte';
	import LevelPill from './LevelPill.svelte';
	import { ADD_LABELS, DATASET_TITLES } from './labels.ts';
	import { loadReference } from './reference.ts';

	let { dataset }: { dataset: Dataset } = $props();

	const LEVELS = [{ value: '', label: 'All' }, ...['N5', 'N4', 'N3', 'N2', 'N1'].map((l) => ({ value: l, label: l }))];

	let items = $state<ItemSummary[] | null>(null);
	let version = $state('');
	let readings = $state<Record<string, string>>({});
	let forms = $state<Record<string, string>>({});
	let additions = $state<Suggestion[]>([]);
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
		loadReference().then((reference) => {
			readings = reference.readings;
			forms = reference.forms;
		});
		refreshAdditions();
	});

	function refreshAdditions() {
		getAdditions(dataset)
			.then((list) => (additions = list))
			.catch(() => (additions = []));
	}

	const shown = $derived(browseFilter(items ?? [], search, level));

	const href = (item: ItemSummary) => `/item?${new URLSearchParams({ dataset, id: item.item_id })}`;
</script>

<div class="heading">
	<h1>{DATASET_TITLES[dataset]}</h1>
	{#if version}<p class="version">Version {version}</p>{/if}
	<a class="suggest-new" href="/add?dataset={dataset}">{ADD_LABELS[`${dataset}/entry`]}</a>
</div>

{#if additions.length}
	<section class="additions" aria-labelledby="additions-heading">
		<h2 id="additions-heading">Suggested additions</h2>
		{#each additions as s (s.id)}
			<SuggestionCard
				suggestion={s}
				current={null}
				names={[]}
				{readings}
				{forms}
				onwithdraw={async () => {
					await withdrawSuggestion(s.id);
					refreshAdditions();
				}}
				oncomment={async (text) => {
					await comment(s.id, text);
					refreshAdditions();
				}}
			/>
		{/each}
	</section>
{/if}

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
		<div class="levels"><FilterChips label="JLPT level" options={LEVELS} bind:value={level} /></div>
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
						{#if item.approved || item.open}
							<span class="reviews">
								{#if item.approved}<span class="approved">{item.approved} of {item.targets} approved</span>{/if}
								{#if item.open}<span class="open">{item.open} open {item.open === 1 ? 'suggestion' : 'suggestions'}</span>{/if}
							</span>
						{/if}
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

	.suggest-new {
		margin-left: auto;
		font-size: 0.95rem;
	}

	.additions {
		max-width: 42rem;
		margin-top: 1.25rem;
	}

	.additions h2 {
		margin: 0;
		font-size: 1.05rem;
		font-weight: 500;
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

	.levels {
		display: flex;
		align-items: center;
		min-width: 0;
		max-width: 100%;
	}

	.items {
		margin: 0;
		padding: 0;
		list-style: none;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	.reviews {
		grid-column: 1 / -1;
		display: flex;
		flex-wrap: wrap;
		gap: 0 1rem;
		font-size: 0.85rem;
	}

	.approved {
		color: var(--muted);
	}

	.open {
		color: var(--red);
	}

	.items li + li {
		border-top: 1px solid var(--rule);
	}

	.items a {
		display: grid;
		grid-template-columns: minmax(0, 1fr) auto;
		gap: 0.15rem 1rem;
		min-height: 44px;
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

	@media (max-width: 720px) {
		.filters {
			flex-direction: column;
			align-items: stretch;
		}

		.search {
			flex: none;
		}

		.suggest-new {
			margin-left: 0;
			display: inline-flex;
			align-items: center;
			min-height: 44px;
			padding: 0 1.1rem;
			border: 1.5px solid var(--ink);
			border-radius: 999px;
			text-decoration: none;
			flex-basis: 100%;
			justify-content: center;
		}
	}
</style>
