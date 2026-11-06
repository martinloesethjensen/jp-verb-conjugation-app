<script lang="ts">
	// One target shown on its own (the queue card): a sentence on the genkō grid, or the fields that
	// make up an entry, usage, pitfall or thing.
	import Japanese from './Japanese.svelte';
	import LevelPill from './LevelPill.svelte';
	import Sentence from './Sentence.svelte';
	import { FITS } from './labels.ts';
	import { entryTitle } from './targets.ts';

	type Json = { [key: string]: any };

	let {
		dataset,
		kind,
		value,
		readings,
		forms
	}: { dataset: string; kind: string; value: Json; readings: Record<string, string>; forms: Record<string, string> } =
		$props();
</script>

{#if typeof value.jp === 'string'}
	<Sentence
		jp={value.jp}
		en={value.en ?? ''}
		{readings}
		extra={value.readings ?? {}}
		label={value.form ? (forms[value.form] ?? value.form) : undefined}
	/>
{:else if kind === 'entry'}
	<div class="fields">
		<p class="title"><Japanese text={entryTitle(dataset, value)} {readings} /> <LevelPill level={value.jlpt} /></p>
		{#if value.meaning}<p>{value.meaning}</p>{/if}
		{#if value.summary}<p><Japanese text={value.summary} {readings} prose /></p>{/if}
		{#if value.description}<p><Japanese text={value.description} {readings} prose /></p>{/if}
		{#if value.notes}<p><Japanese text={value.notes} {readings} prose /></p>{/if}
	</div>
{:else if kind === 'thing'}
	<div class="fields">
		<p class="title"><Japanese text={value.word} {readings} /> <span class="quiet" lang="ja">{value.kana}</span></p>
		<p>{value.meaning} <span class="quiet">{FITS[value.fit] ?? value.fit}</span></p>
	</div>
{:else}
	<div class="fields">
		<p class="title"><Japanese text={value.heading ?? ''} {readings} prose /> <LevelPill level={value.jlpt} /></p>
		{#if value.explanation}<p><Japanese text={value.explanation} {readings} prose /></p>{/if}
		{#if value.wrong}<p class="quiet">Not: <s lang="ja">{value.wrong}</s></p>{/if}
	</div>
{/if}

<style>
	.fields p {
		margin: 0 0 0.5rem;
	}

	.title {
		font-size: 1.3rem;
	}

	.fields :global(rt) {
		font-size: 0.5em;
		color: var(--muted);
	}

	.quiet {
		color: var(--muted);
	}
</style>
