<script lang="ts">
	// One entry with every authored field. The address is /item?dataset=…&id=…: prerendering can't
	// see the query, so it is read once the page is in the browser.
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { ApiError, DATASETS, getItem, problem, type Dataset, type Field, type ItemResponse } from '#lib/api.ts';
	import ReviewBar from '#lib/ReviewBar.svelte';
	import { EntryReview } from '#lib/review.svelte.ts';
	import { entryTitle } from '#lib/targets.ts';
	import Japanese from '#lib/Japanese.svelte';
	import LevelPill from '#lib/LevelPill.svelte';
	import Sentence from '#lib/Sentence.svelte';
	import { DATASET_TITLES, FITS, WORD_CLASSES } from '#lib/labels.ts';
	import { loadReference } from '#lib/reference.ts';

	// Published entries are loosely typed JSON here; the Worker has already checked their shape.
	type Json = { [key: string]: any };

	let dataset = $state<Dataset | null>(null);
	let response = $state<ItemResponse | null>(null);
	let readings = $state<Record<string, string>>({});
	let forms = $state<Record<string, string>>({});
	let failure = $state<string | null>(null);
	let fieldTable = $state<Record<string, Field[]>>({});
	let review = $state<EntryReview | null>(null);
	let reviewFailure = $state<string | null>(null);

	const item = $derived((response?.item ?? {}) as Json);

	onMount(() => {
		const params = page.url.searchParams;
		const name = params.get('dataset') ?? '';
		const id = params.get('id');
		if (!(DATASETS as readonly string[]).includes(name) || !id) {
			failure = 'This link is missing which item to show.';
			return;
		}
		dataset = name as Dataset;
		const entryReview = new EntryReview(dataset, id);
		entryReview
			.load()
			.then(() => (review = entryReview))
			.catch((error) => (reviewFailure = problem(error)));
		getItem(dataset, id)
			.then((r) => (response = r))
			.catch((error) => {
				failure = error instanceof ApiError ? error.message : 'Something went wrong. Try again in a minute.';
			});
		loadReference().then((reference) => {
			readings = reference.readings;
			forms = reference.forms;
			fieldTable = reference.fields;
		});
	});

	const title = $derived(dataset ? entryTitle(dataset, item) : '');
	const list = (value: unknown): Json[] => (Array.isArray(value) ? value : []);
</script>

<svelte:head>
	<title>{title || 'Item'} · Kotoba Table review</title>
</svelte:head>

{#snippet bar(kind: string, id: string, value: Json, extra: Record<string, string> = {})}
	{#if review && dataset}
		<ReviewBar {review} {kind} {id} {value} fields={fieldTable[`${dataset}/${kind}`] ?? []} {readings} {forms} {extra} />
	{/if}
{/snippet}

{#snippet examples(owner: Json, extraOf: (ex: Json) => Record<string, string> = (ex) => ex.readings ?? {})}
	{#each list(owner.examples) as ex (ex.id)}
		<div class="reviewable" id={ex.id}>
			<Sentence jp={ex.jp} en={ex.en} {readings} extra={extraOf(ex)} label={ex.form ? (forms[ex.form] ?? ex.form) : undefined} />
			{@render bar('example', ex.id, ex, extraOf(ex))}
		</div>
	{/each}
{/snippet}

{#snippet sections(heading: string, owner: Json, key: string, kind: string)}
	{#if list(owner[key]).length}
		<section class="card">
			<h2>{heading}</h2>
			{#each list(owner[key]) as section (section.id)}
				<article class="part" id={section.id}>
					<div class="part-heading">
						<h3><Japanese text={section.heading} {readings} prose /></h3>
						<LevelPill level={section.jlpt} />
					</div>
					<p><Japanese text={section.explanation} {readings} prose /></p>
					{#if section.wrong}<p class="wrong">Not: <s lang="ja">{section.wrong}</s></p>{/if}
					{@render bar(kind, section.id, section)}
					{@render examples(section)}
				</article>
			{/each}
		</section>
	{/if}
{/snippet}

{#if failure}
	<p class="notice" role="alert">{failure}</p>
{:else if !response || !dataset}
	<p class="quiet">Loading…</p>
{:else}
	<p class="back"><a href="/browse/{dataset}">Back to {DATASET_TITLES[dataset].toLowerCase()}</a></p>
	<header class="item-header">
		<h1><Japanese text={title} {readings} /></h1>
		<LevelPill level={item.jlpt} />
	</header>
	{#if reviewFailure}<p class="notice" role="alert">Reviews couldn't be loaded: {reviewFailure}</p>{/if}

	{#if dataset === 'verbs'}
		<section class="card fields">
			<p class="subtitle">{item.meaning}</p>
			<p class="quiet">{item.label}</p>
			{#if item.description}<p><Japanese text={item.description} {readings} prose /></p>{/if}
			{#if item.notes}<p><Japanese text={item.notes} {readings} prose /></p>{/if}
			{@render bar('entry', response.id, item)}
		</section>
		{#if list(item.examples).length}
			<section class="card"><h2>Examples</h2>{@render examples(item)}</section>
		{/if}
		{#if list(item.collocations).length}
			<section class="card">
				<h2>Common phrases</h2>
				{#each list(item.collocations) as c (c.id)}
					<div class="reviewable" id={c.id}>
						<Sentence jp={c.jp} en={c.en} {readings} />
						{@render bar('collocation', c.id, c)}
					</div>
				{/each}
			</section>
		{/if}
	{:else if dataset === 'words'}
		<section class="card fields">
			<p class="subtitle">{item.meaning}</p>
			<p class="quiet">{WORD_CLASSES[item.class] ?? item.class}</p>
			{@render bar('entry', response.id, item)}
		</section>
	{:else if dataset === 'counters'}
		<section class="card fields">
			<p class="subtitle">{item.meaning}</p>
			{@render bar('entry', response.id, item)}
		</section>
		{#if list(item.things).length}
			<section class="card">
				<h2>Things it counts</h2>
				<ul class="things">
					{#each list(item.things) as thing (thing.id)}
						<li id={thing.id}>
							<span class="thing-word"><Japanese text={thing.word} {readings} /></span>
							<span class="quiet" lang="ja">{thing.kana}</span>
							<span>{thing.meaning}</span>
							<span class="quiet">{FITS[thing.fit] ?? thing.fit}</span>
							<div class="thing-review">{@render bar('thing', thing.id, thing)}</div>
						</li>
					{/each}
				</ul>
			</section>
		{/if}
		{#if list(item.examples).length}
			<section class="card"><h2>Examples</h2>{@render examples(item)}</section>
		{/if}
		{@render sections('Pitfalls', item, 'pitfalls', 'pitfall')}
		{#if list(item.questions).length}
			<section class="card">
				<h2>Questions</h2>
				{#each list(item.questions) as q, i (i)}<Sentence jp={q.jp} en={q.en} {readings} extra={q.readings ?? {}} />{/each}
			</section>
		{/if}
	{:else}
		<section class="card fields">
			<p><Japanese text={item.summary} {readings} prose /></p>
			{@render bar('entry', response.id, item)}
		</section>
		{@render sections('Usages', item, 'usages', 'usage')}
		{@render sections('Pitfalls', item, 'pitfalls', 'pitfall')}
		{#if list(item.contrasts).length}
			<section class="card">
				<h2>Compared with</h2>
				{#each list(item.contrasts) as contrast, i (i)}
					<article class="part">
						<h3><Japanese text={contrast.pattern} {readings} prose /></h3>
						<p><Japanese text={contrast.explanation} {readings} prose /></p>
						{@render examples(contrast)}
					</article>
				{/each}
			</section>
		{/if}
	{/if}
{/if}

<style>
	.back {
		margin: 0 0 1rem;
	}

	.item-header {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: 0.5rem 1rem;
		max-width: 42rem;
	}

	h1 {
		margin: 0 0 1rem;
		font-size: 2rem;
		font-weight: 500;
	}

	h1 :global(rt),
	h3 :global(rt),
	.thing-word :global(rt),
	.fields :global(rt),
	.part > p :global(rt) {
		font-size: 0.5em;
		color: var(--muted);
	}

	h2 {
		margin: 0 0 0.5rem;
		font-size: 1.05rem;
		font-weight: 500;
	}

	h3 {
		margin: 0;
		font-size: 1rem;
		font-weight: 500;
	}

	.card {
		max-width: 42rem;
		margin-bottom: 1.25rem;
		padding: 1.25rem 1.5rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	.fields p {
		margin: 0 0 0.5rem;
	}

	.fields p:last-child {
		margin-bottom: 0;
	}

	.subtitle {
		font-size: 1.15rem;
	}

	.quiet {
		color: var(--muted);
	}

	.part + .part {
		margin-top: 1rem;
		padding-top: 1rem;
		border-top: 1px solid var(--rule);
	}

	.part-heading {
		display: flex;
		align-items: baseline;
		gap: 0.75rem;
	}

	.part > p {
		margin: 0.35rem 0;
	}

	.wrong {
		color: var(--muted);
	}

	.things {
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.things li {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: 0.25rem 1rem;
		padding: 0.5rem 0;
	}

	.things li + li {
		border-top: 1px solid var(--rule);
	}

	.thing-review {
		flex-basis: 100%;
	}

	.reviewable {
		padding-bottom: 0.5rem;
	}

	.reviewable + .reviewable {
		border-top: 1px solid var(--rule);
	}

	.thing-word {
		font-size: 1.2rem;
	}

	.notice {
		max-width: 34rem;
		padding: 0.75rem 1rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}
</style>
