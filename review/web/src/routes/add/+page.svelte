<script lang="ts">
	// Suggesting a new verb, word, counter or grammar point. The address is /add?dataset=…, read once the
	// page is in the browser.
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { addItem, DATASETS, type Dataset, type Field, type Suggestion } from '#lib/api.ts';
	import SuggestForm from '#lib/SuggestForm.svelte';
	import { ADD_LABELS, ADD_NOTE, DATASET_TITLES } from '#lib/labels.ts';
	import { loadReference } from '#lib/reference.ts';

	let dataset = $state<Dataset | null>(null);
	let failure = $state<string | null>(null);
	let fields = $state<Field[] | null>(null);
	let readings = $state<Record<string, string>>({});
	let forms = $state<Record<string, string>>({});
	let sent = $state<Suggestion | null>(null);
	/** Remounts the form for another suggestion. */
	let round = $state(0);

	onMount(() => {
		const name = page.url.searchParams.get('dataset') ?? '';
		if (!(DATASETS as readonly string[]).includes(name)) {
			failure = 'This link is missing what to add.';
			return;
		}
		dataset = name as Dataset;
		loadReference().then((reference) => {
			readings = reference.readings;
			forms = reference.forms;
			fields = reference.add_fields[`${name}/entry`] ?? [];
		});
	});

	const defaults = $derived(Object.fromEntries((fields ?? []).filter((f) => f.default).map((f) => [f.name, f.default])));
	const heading = $derived(dataset ? ADD_LABELS[`${dataset}/entry`] : 'Suggest something new');

	function another() {
		sent = null;
		round++;
	}
</script>

<svelte:head>
	<title>{heading} · Kotoba Table review</title>
</svelte:head>

{#if failure}
	<p class="notice" role="alert">{failure}</p>
{:else if dataset}
	<p class="back"><a href="/browse/{dataset}">Back to {DATASET_TITLES[dataset].toLowerCase()}</a></p>
	<h1>{heading}</h1>
	{#if sent}
		<section class="card sent" role="status">
			<p class="lead">Sent. Martin will look at it.</p>
			<p><span lang="ja">{sent.item_title}</span> is listed under the suggested additions.</p>
			<p class="links">
				<a href="/browse/{dataset}">Back to {DATASET_TITLES[dataset].toLowerCase()}</a>
				<button type="button" class="link" onclick={another}>Suggest another</button>
			</p>
		</section>
	{:else if fields === null}
		<p class="quiet">Loading…</p>
	{:else if !fields.length}
		<p class="notice">Martin hasn't loaded this data yet.</p>
	{:else}
		<section class="card">
			{#key round}
				<SuggestForm
					{fields}
					current={{}}
					initial={defaults}
					{readings}
					{forms}
					submitLabel="Suggest adding it"
					hint={ADD_NOTE}
					conflictIsStale={false}
					onsubmit={async (values, furigana) => {
						sent = await addItem(dataset!, 'entry', null, values, {
							furigana: Object.keys(furigana).length ? furigana : undefined
						});
					}}
					oncancel={() => history.back()}
				/>
			{/key}
			<p class="quiet">Already suggested by someone? The list on the <a href="/browse/{dataset}">{DATASET_TITLES[dataset].toLowerCase()} page</a> shows what's waiting.</p>
		</section>
	{/if}
{/if}

<style>
	.back {
		margin: 0 0 1rem;
	}

	h1 {
		margin: 0 0 1rem;
		font-size: 1.5rem;
		font-weight: 500;
	}

	.card {
		max-width: 42rem;
		padding: 1rem 1.25rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}

	.lead {
		margin-top: 0;
		font-size: 1.15rem;
		font-weight: 500;
	}

	.links {
		display: flex;
		flex-wrap: wrap;
		gap: 0.5rem 1rem;
		align-items: center;
	}

	.quiet {
		font-size: 0.9rem;
		color: var(--muted);
	}

	.notice {
		max-width: 34rem;
		padding: 0.75rem 1rem;
		background: var(--card);
		border: 1px solid var(--rule);
		border-radius: var(--radius);
	}
</style>
