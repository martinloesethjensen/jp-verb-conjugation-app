<script lang="ts">
	// What you've approved and suggested, and where each change stands: in the app, waiting, or declined.
	import { onMount } from 'svelte';
	import { ApiError, getContributions, type Change, type Contributions } from '#lib/api.ts';
	import ContributionRow from '#lib/ContributionRow.svelte';
	import {
		countTiles,
		filterCounts,
		headline,
		longDate,
		releaseLine,
		ROLE_PILL,
		splitAccepted,
		type ContributionFilter
	} from '#lib/contributions.ts';
	import ErrorLine from '#lib/ErrorLine.svelte';
	import FilterChips from '#lib/FilterChips.svelte';
	import { CREDIT_ROLES, DATASET_TITLES } from '#lib/labels.ts';
	import { loadReference } from '#lib/reference.ts';
	import Seal from '#lib/Seal.svelte';
	import { getSession } from '#lib/session.ts';

	const { me } = getSession();

	let data = $state<Contributions | null>(null);
	let failure = $state<string | null>(null);
	let readings = $state<Record<string, string>>({});
	let filter = $state<ContributionFilter>('all');

	onMount(() => {
		getContributions()
			.then((result) => (data = result))
			.catch(
				(error) =>
					(failure = error instanceof ApiError ? error.message : 'Something went wrong. Try again in a minute.')
			);
		loadReference().then((reference) => (readings = reference.readings));
	});

	const counts = $derived(data ? filterCounts(data) : null);
	const options = $derived([
		{ value: 'all', label: 'All', count: counts?.all },
		{ value: 'live', label: 'In the app', count: counts?.live },
		{ value: 'waiting', label: 'Waiting', count: counts?.waiting },
		{ value: 'declined', label: 'Declined', count: counts?.declined }
	]);
	const showLive = $derived(filter === 'all' || filter === 'live');
	const showWaiting = $derived(filter === 'all' || filter === 'waiting');
	const showDeclined = $derived(filter === 'all' || filter === 'declined');
	const empty = $derived(!!data && data.counts.approved + data.counts.suggested === 0);
	// Accepted notes never ship, so they don't wait for a release: their own section, under All only.
	const accepted = $derived(data ? splitAccepted(data.accepted) : { next: [], notes: [] });
	const sections = $derived(
		data
			? [
					{ id: 'accepted', title: 'Accepted, in the next release', show: showWaiting, group: 'accepted' as const, list: accepted.next },
					{ id: 'waiting', title: 'Waiting for a decision', show: showWaiting, group: 'waiting' as const, list: data.waiting },
					{ id: 'declined', title: 'Declined', show: showDeclined, group: 'declined' as const, list: data.declined },
					{ id: 'notes', title: 'Notes accepted', show: filter === 'all', group: 'note' as const, list: accepted.notes }
				].filter((s) => s.show && s.list.length)
			: []
	);
	const nothingShown = $derived(!!data && !(showLive && data.releases.length) && !sections.length);
	const key = (c: Change) => c.id;
</script>

<svelte:head>
	<title>Your contributions · Kotoba Table review</title>
</svelte:head>

<header class="top">
	<div>
		<p class="lbl">Your contributions</p>
		<h1>{data ? headline(data) : 'Your contributions'}</h1>
		<p class="quiet">What you've approved and suggested, and where each change stands.</p>
	</div>
	<Seal name={me().display_name} />
</header>

<ErrorLine message={failure} />

{#if data}
	<dl class="counts">
		{#each countTiles(data.counts) as tile (tile.label)}
			<div><dt>{tile.label}</dt><dd class={{ good: tile.good }}>{tile.n}</dd></div>
		{/each}
	</dl>

	{#if empty}
		<p class="empty">Nothing yet. Approve or suggest a change in any queue and it shows up here.</p>
	{:else}
		<div class="layout">
			<div class="main">
				<FilterChips label="Show" {options} bind:value={filter} />

				{#if nothingShown}
					<p class="quiet">Nothing here yet.</p>
				{/if}

				{#if showLive}
					{#each data.releases as release, i (release.label)}
						<section aria-labelledby="release-{i}">
							<div class="head">
								<h2 id="release-{i}">
									{release.loaded_at ? `Release ${release.label}` : release.label}
								</h2>
								<p class="quiet">{releaseLine(release, longDate)}</p>
							</div>
							<ul>
								{#each release.changes as change (key(change))}
									<ContributionRow {change} group="release" {readings} />
								{/each}
							</ul>
						</section>
					{/each}
				{/if}

				{#each sections as section (section.id)}
					<section aria-labelledby="{section.id}-heading">
						<div class="head"><h2 id="{section.id}-heading">{section.title}</h2></div>
						<ul>
							{#each section.list as change (key(change))}
								<ContributionRow {change} group={section.group} {readings} />
							{/each}
						</ul>
					</section>
				{/each}
			</div>

			<aside>
				<section class="credit" aria-labelledby="credit-heading">
					<h2 id="credit-heading">Your credit in the app</h2>
					<p class="name">{data.credit.name ?? `Credited as ${CREDIT_ROLES[data.credit.role]}`}</p>
					<p><span class="pill">{ROLE_PILL[data.credit.role]}</span></p>
					<p><a href="/settings">Change how you're credited</a></p>
				</section>
				<section class="datasets" aria-labelledby="sets-heading">
					<h2 id="sets-heading">By data set</h2>
					<dl>
						{#each data.datasets as set (set.dataset)}
							<dt>{DATASET_TITLES[set.dataset as keyof typeof DATASET_TITLES] ?? set.dataset}</dt>
							<dd>{set.approved} approved · {set.suggested} suggested</dd>
						{/each}
					</dl>
				</section>
			</aside>
		</div>
	{/if}
{:else if !failure}
	<p class="quiet">Loading…</p>
{/if}

<style>
	.top {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: 1.5rem;
		margin-top: 1.5rem;
	}

	.lbl {
		margin: 0;
		font-size: 11px;
		font-weight: 700;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--muted);
	}

	h1 {
		margin: 0.25rem 0 0.25rem;
		font-size: 34px;
	}

	.quiet {
		margin: 0;
		color: var(--muted);
	}

	.counts {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: 1px;
		margin: 1.5rem 0;
		overflow: hidden;
		background: var(--rule);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	.counts div {
		display: flex;
		flex-direction: column-reverse;
		padding: 0.9rem 1.25rem;
		background: var(--card);
	}

	.counts dd {
		margin: 0;
		font-size: 1.9rem;
		font-weight: 700;
		line-height: 1.2;
	}

	.counts dt {
		font-size: 0.85rem;
		color: var(--muted);
	}

	.good {
		color: var(--green);
	}

	.layout {
		display: grid;
		grid-template-columns: minmax(0, 1fr) 18rem;
		gap: 1.5rem;
		align-items: start;
	}

	.main {
		display: grid;
		gap: 1.25rem;
		min-width: 0;
	}

	section {
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	.head {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: 0.25rem 0.75rem;
		padding: 1rem 1.25rem 0.75rem;
	}

	h2 {
		margin: 0;
		font-size: 1.15rem;
	}

	ul {
		margin: 0;
		padding: 0;
		list-style: none;
	}

	aside {
		display: grid;
		gap: 1rem;
	}

	aside section {
		padding: 1rem 1.25rem;
	}

	aside p {
		margin: 0.5rem 0 0;
	}

	.name {
		font-weight: 700;
	}

	aside a {
		display: inline-flex;
		align-items: center;
		min-height: 44px;
	}

	.pill {
		display: inline-block;
		padding: 0 0.7rem;
		border: 1px solid var(--ink);
		border-radius: 999px;
		font-size: 0.85rem;
		font-weight: 500;
	}

	aside dl {
		display: grid;
		grid-template-columns: auto 1fr;
		gap: 0.35rem 1rem;
		margin: 0.5rem 0 0;
	}

	aside dt {
		font-weight: 700;
	}

	aside dd {
		margin: 0;
		color: var(--muted);
		text-align: right;
	}

	.empty {
		padding: 1.5rem;
		background: var(--card);
		border: 1px dashed var(--rule);
		border-radius: var(--radius);
		color: var(--muted);
	}

	@media (max-width: 720px) {
		h1 {
			font-size: 1.65rem;
		}

		.counts {
			grid-template-columns: repeat(2, 1fr);
		}

		.layout {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
